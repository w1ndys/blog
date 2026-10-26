# w1ndys 的博客

技术踩坑、服务运维与随手记。

- 线上：<https://yt-blog.top>（Vercel，换域名只改 `astro.config.mjs` 的 `site`）
- 框架：Astro 7 静态输出 + MDX + Shiki 代码高亮，零客户端 JS
- 订阅：`/rss.xml`

## 本地开发

```bash
pnpm install
pnpm dev      # http://localhost:4321
pnpm build    # 产物在 dist/
pnpm preview  # 预览构建结果
```

Node ≥ 22。

## 目录

```
src/
├─ content/blog/      # 文章：YYYY-MM-DD-slug.md
├─ components/        # 头部、页脚、日期等
├─ layouts/           # 文章页骨架
├─ lib/posts.ts       # 取文章 / 过滤草稿 / 统计标签
├─ pages/
│  ├─ index.astro     # 首页（最新文章）
│  ├─ blog/           # 文章列表与详情
│  ├─ tags/           # 标签聚合
│  ├─ about.astro
│  └─ rss.xml.js
├─ styles/global.css
└─ consts.ts          # 站点标题、描述、作者
```

## 写一篇

在 `src/content/blog/` 新建 `YYYY-MM-DD-slug.md`：

```yaml
---
title: 标题
description: 一句话摘要，列表页和 RSS 都用它
pubDate: 2026-10-26
tags: [docker, caddy]
draft: false
---

正文……
```

字段类型的唯一事实来源是 `src/content.config.ts`（zod schema）。`draft: true` 的文章只在 `pnpm dev` 下可见。

## 内容的边界

这里只发经过挑选和脱敏的内容：不包含内网地址、凭据、他人信息。写作与公开规则见 [AGENTS.md](AGENTS.md)。

## License

文章内容版权归作者所有；代码片段可自由取用。
