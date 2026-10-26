# 这个仓库怎么用（给 Agent 的工作约定）

`w1ndys` 的公开技术博客：Astro + [Firefly](https://github.com/CuteLeaf/Firefly) 主题，静态输出，部署在 Vercel（`blog.w1ndys.top`）。本文只讲**在这里做事要遵守什么**，站点结构见 `README.md`。

## 最重要的一条：内容默认不写这里

- **所有新的记录、踩坑、决策、运维日志，默认写进私有笔记仓**，不是这个仓库。
- 只有用户**明确说过「这个可以放到博客上」**（或等价的明确授权），才把对应内容搬到本仓发布。
- 没有明确授权时，**不要**擅自把私有仓的内容"顺手"整理成文章，也不要提议某篇"看起来可以公开"。判断是否公开是用户的事，不是 Agent 的。
- 用户的口头授权只对该篇有效，不推广到同类主题，不构成先例。

## 搬到本仓之前必须脱敏

授权之后，逐项过一遍，命中就删或替换成占位符：

| 类型 | 处理 |
|---|---|
| 公网 IP、VPS 地址、家庭出口 IP | 换成 `VPS_IP` / `HOME_IP` 或删掉整句 |
| 内网 / 隧道 / 容器拓扑、端口清单 | 不公开 |
| 自有域名与子域结构的完整清单 | 只留示例域名，或改写成 `example.com` |
| 凭据：AppID/AppSecret、Token、AESKey、JWT secret、密码、私钥 | **绝不出现**，示例一律 `YOUR_TOKEN` |
| 真实用户 / 群 / 账号标识（群号、OpenID、微信号、昵称） | 不公开 |
| 第三方服务的内部配置、其他人的机器信息 | 不公开 |

脱敏不是"复制过去再删"：先在本仓新建文章，只粘授权范围内的技术内容，再补写上下文。宁可写得短，也不要带着内部信息发出去。

## 写一篇

- 位置 `src/content/posts/`，命名 `YYYY-MM-DD-slug.md`（需要组件时用 `.mdx`）。
- 必填只有 `title` 和 `published`；其余按需：

  ```yaml
  ---
  title: 标题
  published: 2026-10-26
  description: 一句话摘要，列表和 RSS 都用它
  tags: [docker, caddy]
  category: 运维
  draft: false      # true 时不出现在列表与 RSS
  pinned: false     # true 会置顶
  ---
  ```

- 字段约束的唯一事实来源是 `src/content.config.ts`（zod schema），写错构建直接报错。
- 技术细节优先原样保留：命令、版本号、报错原文。这些比结论更有复用价值。
- 标签用英文小写短词，一篇文章不超过五个。

## 站点配置在哪（Firefly 的约定，和通用 Astro 主题不同）

配置集中在 `src/config/`，`astro.config.mjs` 里没有硬编码的 site（它读 `siteConfig.site_url`）：

| 文件 | 管什么 |
|---|---|
| `siteConfig.ts` | 站点标题、副标题、`site_url`、描述、语言（`zh_CN`）、页面开关 |
| `profileConfig.ts` | 头像、昵称、bio、社交链接 |
| `navBarConfig.ts` | 导航栏与右上角外链 |
| `displaySettingsConfig.ts` | 布局、横幅、目录等显示项 |
| 其余 `*Config.ts` | 相册、动态、友链、书签、音乐、打赏等，对应页面在 `siteConfig.pages` 里开关 |

当前把 `friends` / `guestbook` / `dynamic` / `projects` / `gallery` / `booknav` / `sponsor` 都关了（关掉即返回 404 并隐藏导航项），只留文章、标签、归档、关于。要用某个功能时先清理它自带的示例数据，再打开开关。

## 技术约定

- 包管理器 `pnpm`，Node ≥ 22。
- 页面级静态内容放 `src/content/`；需要交互的组件才用 Svelte（主题已带）。
- 搜索基于 Pagefind，构建时自动索引 `dist`；中文不支持 stemming，搜不到词形变化属预期。
- 改完跑 `pnpm build`，通过再提交；push 到 `main` 由 Vercel 自动部署。
- 提交信息用 `类型(范围): 中文描述`，例如 `feat(post): 新增微信公众平台接入踩坑记录`。
