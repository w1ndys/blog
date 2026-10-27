# 与上游主题对齐

本站是 [Firefly](https://github.com/CuteLeaf/Firefly) 主题的**复制式使用**（不是 fork），主题代码以本文件记录的上游提交为准。日常依赖升级跟随上游提交，不单独接受 dependabot 的 minor/major。

## 当前对齐点

| 项 | 值 |
|---|---|
| 上游仓库 | `CuteLeaf/Firefly` |
| 对齐 commit | `cd920b0`（2026-10-22，`ci: upgrade GitHub Actions to Node.js 24 runtimes (#676)`） |
| 对齐日期 | 2026-10-26 |
| 同步方式 | rsync 覆盖 + 保护清单（见下） |

## 哪些是我们自己的（同步时不能覆盖）

| 路径 | 内容 |
|---|---|
| `src/content/` | 文章（`posts/`）与关于、友链、留言板（`spec/`） |
| `src/config/` | 站点信息、导航、页面开关、头像等全部站点配置 |
| `src/constants/github-card-data.json` | 构建脚本生成的卡片缓存 |
| `src/constants/lqips.json` | 构建脚本生成的图片处理缓存 |
| `README.md` / `AGENTS.md` | 本仓的说明与写作规则 |
| `.github/dependabot.yml` | 已按本仓策略改过（见下） |
| `wrangler.jsonc` | 主题自带的 Cloudflare 配置，本站不用，已删 |
| `public/` 下的自有资源 | 自传图片等（同步后检查有没有被示例资源覆盖） |

## 同步流程

```bash
scripts/sync-upstream.sh            # 默认跟随上游 main
scripts/sync-upstream.sh <sha|tag>  # 对齐到指定提交
```

脚本做四件事：备份当前 HEAD 到 `sync-backup-<时间戳>` 分支 → 克隆上游到临时目录 → 按保护清单 rsync 覆盖 → `pnpm install && pnpm build` 验证。任何一步失败都会停下，改动留在工作区可回滚。

成功之后手动做两件事：

1. 把本文件「当前对齐点」的 commit 与日期改掉
2. `git diff --stat` 过一遍，确认只有主题文件变化；`git push` 后看 Vercel 部署是否通过

## 上游待合并的相关 PR（2026-10-26 观察）

| PR | 内容 | 对本站的影响 |
|---|---|---|
| [#679](https://github.com/CuteLeaf/Firefly/pull/679) | 防止清空内容目录后构建仍保留旧动态和项目 | 我们清空过 `dynamic/`、`projects/`，合并后值得跟一次 |
| [#680](https://github.com/CuteLeaf/Firefly/pull/680) | 同步 Biome 2.6.2 并排除 Markdown 内容文件 | 与 dependabot 的 `@biomejs/biome` 冲突，等上游合 |
| [#690](https://github.com/CuteLeaf/Firefly/pull/690) / [#691](https://github.com/CuteLeaf/Firefly/pull/691) | 上游自己的 dependabot minor / patch 组 | 上游同样没合，说明不跟 dependabot 是共同做法 |

## dependabot 策略

- `interval: weekly`（上游模板默认 daily，噪音太大）
- 只保留 patch 分组；minor / major 一律 ignore，跟随上游
- `@mermanjs/web` 连 patch 也 ignore：它是 `0.x`，0.8.0-alpha.3 → 0.9.2 移除了 `assertSafeSvgForDom` 导出与 `pkg/merman_wasm_bg.wasm` 子路径，属于 0.x 允许的 breaking；`src/plugins/rehype-mermaid.mjs` 依赖这两处，升级要单独适配
- `@astrojs/cloudflare`、`wrangler` 是模板残留（本站只部署 Vercel），若上游不清理，动它们之前先确认没有脚本引用

## 历史对齐记录

| 日期 | 上游 commit | 说明 |
|---|---|---|
| 2026-10-26 | `cd920b0` | 首次引入主题（AstroPaper 对比后选定），删除示例内容、关闭多余页面、重写 AGENTS/README |
