# w1ndys 的博客

技术踩坑、服务运维与随手记。

- 线上：<https://blog.w1ndys.top>
- 主题：[Firefly](https://github.com/CuteLeaf/Firefly)（基于 [Fuwari](https://github.com/saicaca/fuwari)）
- 框架：Astro 7 + Svelte islands，静态输出，零后端
- 订阅：`/rss.xml` ｜ 搜索：Pagefind（构建时索引）
- 部署：Vercel，push 到 `main` 自动发布

## 本地开发

```bash
pnpm install
pnpm dev      # http://localhost:4321
pnpm build    # 产物在 dist/（含 Pagefind 索引）
```

Node ≥ 22。

## 目录

```
src/
├─ content/
│  ├─ posts/         # 文章：YYYY-MM-DD-slug.md
│  └─ spec/          # 关于、友链、留言板等内容页
├─ config/           # 全站配置（站点信息、导航、布局、各功能页）
├─ pages/            # 路由
├─ layouts/          # 页面骨架
├─ components/       # UI 组件（含 Svelte islands）
└─ styles/           # 样式
public/              # 静态资源
```

站点标题、域名、页面开关在 `src/config/siteConfig.ts`；个人信息在 `src/config/profileConfig.ts`。

## 写一篇

在 `src/content/posts/` 新建 `YYYY-MM-DD-slug.md`：

```yaml
---
title: 标题
published: 2026-10-26
description: 一句话摘要，列表和 RSS 都用它
tags: [docker, caddy]
category: 运维
draft: false
---
```

字段约束由 `src/content.config.ts` 的 zod schema 定义。`draft: true` 的文章不进列表与 RSS。

## 内容的边界

这里只发经过挑选和脱敏的内容：不包含内网地址、凭据、他人信息。写作与公开规则见 [AGENTS.md](AGENTS.md)。

## License

文章内容版权归作者所有；代码片段可自由取用。主题本身遵循 Firefly 仓库的许可。
