import { fetchText } from './fetch.ts';
import { parseFeed } from './parse-feed.ts';
import type { FeedItem, FetchOptions } from './types.ts';

export async function loadRss(
  config: { url: string },
  options: FetchOptions,
): Promise<FeedItem[]> {
  return parseFeed(await fetchText(config.url, options));
}
