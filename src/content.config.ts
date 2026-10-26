import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { z } from 'astro/zod';

// 每篇文章的 frontmatter 契约。字段写错会在 build 时直接报错。
const blog = defineCollection({
	loader: glob({ base: './src/content/blog', pattern: '**/*.{md,mdx}' }),
	schema: ({ image }) =>
		z.object({
			title: z.string(),
			description: z.string(),
			/** 首次发布日期，列表排序依据 */
			pubDate: z.coerce.date(),
			/** 实质更新日期，有就显示 */
			updatedDate: z.coerce.date().optional(),
			/** 标签，用于 /tags/<tag>/ 聚合 */
			tags: z.array(z.string()).default([]),
			/** 草稿：为 true 时不出现在列表与 RSS 中 */
			draft: z.boolean().default(false),
			/** 可选封面，未提供时文章页不渲染图 */
			heroImage: z.optional(image()),
		}),
});

export const collections = { blog };
