import type { PinnedSource } from './resolve.ts';
import type { FeedItem } from './types.ts';

/** No network, no failure mode — a pin is the most reliable source we have. */
export function loadPinned(config: PinnedSource, now: Date): FeedItem[] {
  return config.items
    .filter((item) => !item.expires || item.expires > now)
    .map((item) => ({
      title: item.title,
      url: item.url,
      date: item.date,
      excerpt: item.excerpt,
    }));
}
