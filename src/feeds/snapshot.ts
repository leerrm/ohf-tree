import type { FeedItem } from './types.ts';

/**
 * The build captures every source to src/generated/feed-snapshot.ts and bundles
 * it with the function, so there is always a known-good set of items in memory
 * with no network call and no cold-start penalty.
 *
 * The module is generated, gitignored and may legitimately be absent (a fresh
 * clone, a build where every fetch failed), so the import is deliberately soft.
 */
type Snapshot = Record<string, { title: string; url: string; date?: string; excerpt?: string }[]>;

let cached: Snapshot | undefined;

export async function readSnapshot(key: string): Promise<FeedItem[]> {
  if (!cached) {
    try {
      const module = await import('../generated/feed-snapshot.ts');
      cached = module.snapshot as Snapshot;
    } catch {
      cached = {};
    }
  }

  return (cached[key] ?? []).map((item) => ({
    ...item,
    date: item.date ? new Date(item.date) : undefined,
  }));
}
