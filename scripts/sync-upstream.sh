#!/usr/bin/env bash
# 把博客的主题部分与上游 CuteLeaf/Firefly 对齐。
#
# 主题是「复制式使用」不是 fork，所以同步靠 rsync 覆盖 + 保护清单。
# 保护清单外的文件会被上游版本覆盖，清单内的保持本站现状。
#
# 用法：
#   scripts/sync-upstream.sh                  # 跟随上游 main
#   scripts/sync-upstream.sh <sha|tag|branch> # 对齐到指定提交
#
# 退出码：0 成功；1 前置检查失败；2 同步后构建失败（改动留在工作区）。

set -euo pipefail

UPSTREAM_REPO="https://github.com/CuteLeaf/Firefly.git"
REF="${1:-main}"
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# ── 保护清单：本站自己的内容，同步时一律保留 ─────────────────────────────
PROTECTED=(
  # 版本与依赖
  ".git"
  "node_modules"
  "dist"
  ".astro"
  ".vercel"
  "pnpm-lock.yaml"
  # 内容与站点配置
  "src/content"
  "src/config"
  "src/constants/github-card-data.json"
  "src/constants/lqips.json"
  # 本仓文档与策略
  "README.md"
  "AGENTS.md"
  "CLAUDE.md"
  ".github/dependabot.yml"
  "wrangler.jsonc"
  # 本仓脚本
  "scripts/sync-upstream.sh"
  "docs"
)

# ── 1. 前置检查 ────────────────────────────────────────────────────────
if [[ -n "$(git status --porcelain)" ]]; then
  echo "工作区不干净，先提交或 stash 再同步：" >&2
  git status --short >&2
  exit 1
fi

BACKUP="sync-backup-$(date +%Y%m%d-%H%M%S)"
git branch "$BACKUP"
echo "已备份当前 HEAD 到分支 $BACKUP"

# ── 2. 克隆上游 ────────────────────────────────────────────────────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "克隆 $UPSTREAM_REPO @ $REF ..."
if ! git clone --quiet --depth 1 --branch "$REF" "$UPSTREAM_REPO" "$TMP/upstream" 2>/dev/null; then
  echo "clone 失败（网络或 ref 不存在）。若是深度克隆取不到指定 sha，改用分支名或 tag。" >&2
  exit 1
fi
UPSTREAM_SHA="$(git -C "$TMP/upstream" rev-parse --short HEAD)"
echo "上游版本：$UPSTREAM_SHA"

# ── 3. rsync 覆盖（保护清单排除在外）─────────────────────────────────────
RSYNC_ARGS=(-a --itemize-changes)
for path in "${PROTECTED[@]}"; do
  RSYNC_ARGS+=(--exclude="$path")
done

echo "开始同步（保护清单 ${#PROTECTED[@]} 项不覆盖）..."
rsync "${RSYNC_ARGS[@]}" "$TMP/upstream/" "$ROOT/" | sed 's/^/> /' | head -60

# ── 4. 安装依赖并构建验证 ───────────────────────────────────────────────
echo "安装依赖..."
pnpm install --silent

echo "构建验证..."
if ! pnpm build; then
  echo "构建失败。改动已留在工作区，可用 'git checkout -- .' 回滚，或切到 $BACKUP 对比。" >&2
  exit 2
fi

# ── 5. 收尾提示 ────────────────────────────────────────────────────────
cat <<EOF

同步完成，上游 commit：$UPSTREAM_SHA

接下来手动做：
  1. 更新 docs/upstream.md 的「当前对齐点」（commit 与日期）
  2. git diff --stat 过一遍，确认只有主题文件变化
  3. git add -A && git commit，push 后看 Vercel 部署

回滚：git reset --hard $BACKUP
删除备份分支：git branch -D $BACKUP
EOF
