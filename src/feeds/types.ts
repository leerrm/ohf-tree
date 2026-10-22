import type { SourceConfig } from '../content/schema.ts';

/** The one shape every source resolves to, whatever it came from. */
export interface FeedItem {
  title: string;
  url: string;
  date?: Date;
  excerpt?: string;
}

export type FeedAdapter = (config: never, options: FetchOptions) => Promise<FeedItem[]>;

export interface FetchOptions {
  /** Hard ceiling on a single fetch. The page is never slower than this. */
  timeoutMs: number;
  signal?: AbortSignal;
}

export type { SourceConfig };
