import { XMLParser } from 'fast-xml-parser';
import type { FeedItem } from './types.ts';

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: '@',
  trimValues: true,
});

const asArray = <T>(value: T | T[] | undefined): T[] =>
  value === undefined ? [] : Array.isArray(value) ? value : [value];

const text = (value: unknown): string | undefined => {
  if (typeof value === 'string') return value;
  if (value && typeof value === 'object' && '#text' in value) {
    return String((value as { '#text': unknown })['#text']);
  }
  return undefined;
};

/** Strips tags and collapses whitespace — feed summaries arrive as HTML. */
const plain = (value: string | undefined, max = 160): string | undefined => {
  if (!value) return undefined;
  const stripped = value
    .replace(/<[^>]*>/g, ' ')
    .replace(/&(nbsp|amp|lt|gt|quot|#39);/g, (_, name) =>
      ({ nbsp: ' ', amp: '&', lt: '<', gt: '>', quot: '"', '#39': "'" })[name as string] ?? ' ',
    )
    .replace(/\s+/g, ' ')
    .trim();
  if (!stripped) return undefined;
  return stripped.length > max ? `${stripped.slice(0, max - 1).trimEnd()}…` : stripped;
};

const toDate = (value: string | undefined): Date | undefined => {
  if (!value) return undefined;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? undefined : date;
};

/** Pure feed parsing, shared with scripts/snapshot.mjs — keep it import-light. */
/** Parses both RSS 2.0 and Atom, which is all we need for OHF blogs and Mastodon. */
export function parseFeed(xml: string): FeedItem[] {
  const document = parser.parse(xml) as Record<string, any>;

  const rssItems = asArray(document?.rss?.channel?.item);
  if (rssItems.length > 0) {
    return rssItems
      .map((item): FeedItem | undefined => {
        const title = text(item.title);
        const url = text(item.link);
        if (!url) return undefined;
        return {
          title: plain(title, 90) ?? url,
          url,
          date: toDate(text(item.pubDate)),
          excerpt: plain(text(item.description)),
        };
      })
      .filter((item): item is FeedItem => item !== undefined);
  }

  const atomEntries = asArray(document?.feed?.entry);
  return atomEntries
    .map((entry): FeedItem | undefined => {
      const links = asArray(entry.link);
      const href =
        links.find((link: any) => link?.['@rel'] === 'alternate')?.['@href'] ??
        links[0]?.['@href'] ??
        text(entry.link);
      if (!href) return undefined;
      return {
        title: plain(text(entry.title), 90) ?? href,
        url: href,
        date: toDate(text(entry.published) ?? text(entry.updated)),
        excerpt: plain(text(entry.summary) ?? text(entry.content)),
      };
    })
    .filter((item): item is FeedItem => item !== undefined);
}
