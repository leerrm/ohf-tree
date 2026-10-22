import type { SourceConfig, SourceMap } from '../content/schema.ts';
import { loadGithubReleases } from './github-releases.ts';
import { loadPinned } from './pinned.ts';
import { loadRss } from './rss.ts';
import { readSnapshot } from './snapshot.ts';
import type { FeedItem, FetchOptions } from './types.ts';

export type PinnedSource = Extract<SourceConfig, { type: 'pinned' }>;

/** Each fetch loses to the clock at this point; see the freshness model in the README. */
const DEFAULT_TIMEOUT_MS = 800;

export interface ResolveContext {
  /** The project's full source map, so pins can fall back to a live feed. */
  sources: SourceMap;
  /** Key under which snapshots are stored: `${project}:${source}`. */
  snapshotPrefix: string;
  now?: Date;
  timeoutMs?: number;
  /** Skip the snapshot and let failures throw. Used by the snapshot builder. */
  live?: boolean;
  onWarn?: (message: string) => void;
}

async function load(
  config: SourceConfig,
  options: FetchOptions,
  now: Date,
): Promise<FeedItem[]> {
  switch (config.type) {
    case 'rss':
    case 'mastodon':
      return loadRss(config, options);
    case 'github-releases':
      return loadGithubReleases(config, options);
    case 'pinned':
      return loadPinned(config, now);
  }
}

/**
 * Resolves a named source to items, degrading in order:
 * live result → build-time snapshot → nothing (the caller then renders its
 * curated fallback, or omits the section). A source is never a visible error.
 */
export async function resolveSource(
  name: string,
  context: ResolveContext,
  seen: ReadonlySet<string> = new Set(),
): Promise<FeedItem[]> {
  const config = context.sources[name];
  if (!config) return [];

  // superRefine rejects self-reference, but a longer cycle across several pins
  // would still loop, and a link page is not worth a stack overflow.
  if (seen.has(name)) {
    context.onWarn?.(`Circular source fallback at "${name}"`);
    return [];
  }

  const now = context.now ?? new Date();
  const timeoutMs = context.timeoutMs ?? DEFAULT_TIMEOUT_MS;

  let items: FeedItem[] = [];
  try {
    items = await load(config, { timeoutMs }, now);
  } catch (error) {
    if (context.live) throw error;
    context.onWarn?.(`Source "${name}" failed: ${(error as Error).message}`);
    items = await readSnapshot(`${context.snapshotPrefix}:${name}`);
  }

  // An expired pin is not an error: it means "use the live feed again".
  if (items.length === 0 && config.type === 'pinned' && config.fallback) {
    return resolveSource(config.fallback, context, new Set([...seen, name]));
  }

  return items.sort((a, b) => (b.date?.getTime() ?? 0) - (a.date?.getTime() ?? 0));
}
