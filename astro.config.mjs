// @ts-check

import mdx from '@astrojs/mdx';
import sitemap from '@astrojs/sitemap';
import { defineConfig } from 'astro/config';

// 换域名只改这一处（RSS、sitemap、canonical 都依赖它）
export default defineConfig({
	site: 'https://yt-blog.top',
	integrations: [mdx(), sitemap()],
	markdown: {
		shikiConfig: {
			// 技术博客以亮色阅读环境为主
			theme: 'github-light',
			wrap: true,
		},
	},
});
