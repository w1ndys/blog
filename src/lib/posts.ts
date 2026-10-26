import { getCollection, type CollectionEntry } from 'astro:content';

export type Post = CollectionEntry<'blog'>;

/** 生产构建下过滤草稿；开发时保留，方便预览。 */
export async function getPublishedPosts(): Promise<Post[]> {
	const posts = await getCollection('blog', ({ data }) => import.meta.env.DEV || !data.draft);
	return posts.sort((a, b) => b.data.pubDate.valueOf() - a.data.pubDate.valueOf());
}

/** 统计所有已发布文章的标签及数量，按数量降序。 */
export function collectTags(posts: Post[]): { tag: string; count: number }[] {
	const counter = new Map<string, number>();
	for (const post of posts) {
		for (const tag of post.data.tags) {
			counter.set(tag, (counter.get(tag) ?? 0) + 1);
		}
	}
	return [...counter.entries()]
		.map(([tag, count]) => ({ tag, count }))
		.sort((a, b) => b.count - a.count || a.tag.localeCompare(b.tag));
}
