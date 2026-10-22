import { z } from 'astro/zod';

/**
 * The YAML contract for a project page.
 *
 * Everything a non-developer can express about a page is defined here. A typo,
 * a malformed date or a reference to a source that does not exist fails the
 * build with a pointer to the file, so mistakes surface in the pull request
 * rather than in production.
 */

/** A hand-written link. Campaign tiles live here. */
const linkItem = z.object({
  label: z.string(),
  url: z.url(),
  /** Optional second line, e.g. "Closes 30 November". */
  note: z.string().optional(),
  /** Visual emphasis. Use sparingly — everything featured means nothing is. */
  featured: z.boolean().default(false),
  /** Scheduling window. Outside it the tile is not rendered at all. */
  starts: z.coerce.date().optional(),
  ends: z.coerce.date().optional(),
});

/** An item written by hand into a `pinned` source. */
const pinnedItem = z.object({
  title: z.string(),
  url: z.url(),
  excerpt: z.string().optional(),
  date: z.coerce.date().optional(),
  /** After this moment the pin stops applying and the fallback takes over. */
  expires: z.coerce.date().optional(),
});

/**
 * Sources are a named map, and a pin is a source type like any other. A section
 * asks for a source by name and renders whatever comes back; it never knows
 * whether that was a pin, a blog feed or a release. "Pin this for 48 hours,
 * then go back to the blog" is therefore a YAML edit, not a code change.
 */
const source = z.discriminatedUnion('type', [
  z.object({
    type: z.literal('rss'),
    url: z.url(),
  }),
  z.object({
    type: z.literal('github-releases'),
    repo: z.string().regex(/^[\w.-]+\/[\w.-]+$/, 'Expected "owner/repo"'),
    /** Pre-releases are noise in a bio link unless asked for. */
    includePrereleases: z.boolean().default(false),
  }),
  z.object({
    type: z.literal('mastodon'),
    /** The account's RSS URL, e.g. https://fosstodon.org/@homeassistant.rss */
    url: z.url(),
  }),
  z.object({
    type: z.literal('pinned'),
    items: z.array(pinnedItem).default([]),
    /** Name of another source to serve once no pin is active. */
    fallback: z.string().optional(),
  }),
]);

const section = z.discriminatedUnion('type', [
  z.object({
    type: z.literal('links'),
    title: z.string().optional(),
    items: z.array(linkItem).min(1),
  }),
  z.object({
    type: z.literal('feed'),
    title: z.string().optional(),
    /** Key in the project's `sources` map. Validated after parsing. */
    source: z.string(),
    limit: z.number().int().positive().max(10).default(1),
    /** Shown when the source yields nothing at all. */
    fallback: z.array(linkItem).optional(),
  }),
]);

const social = z.object({
  platform: z.enum([
    'mastodon',
    'instagram',
    'github',
    'youtube',
    'discord',
    'reddit',
    'x',
    'linkedin',
    'bluesky',
    'facebook',
    'tiktok',
    'threads',
    'rss',
    'web',
  ]),
  url: z.url(),
  /** Overrides the accessible label, which defaults to the platform name. */
  label: z.string().optional(),
});

export const projectSchema = z
  .object({
    name: z.string(),
    tagline: z.string().optional(),
    /** Path under /public, e.g. /avatars/home-assistant.svg */
    avatar: z.string().regex(/^\//, 'Must be a path under /public, e.g. /avatars/foo.svg').optional(),
    theme: z
      .object({
        accent: z.string(),
        accentDark: z.string().optional(),
      })
      .optional(),
    sections: z.array(section).default([]),
    socials: z.array(social).default([]),
    sources: z.record(z.string(), source).default({}),
    /** Exclude from the OHF index while keeping the route reachable. */
    unlisted: z.boolean().default(false),
  })
  .superRefine((project, ctx) => {
    const known = new Set(Object.keys(project.sources));

    // A section pointing at a source that does not exist is the single most
    // likely editing mistake, and silently renders nothing. Fail the build.
    project.sections.forEach((entry, index) => {
      if (entry.type === 'feed' && !known.has(entry.source)) {
        ctx.addIssue({
          code: 'custom',
          path: ['sections', index, 'source'],
          message: `Unknown source "${entry.source}". Declared sources: ${
            [...known].join(', ') || '(none)'
          }`,
        });
      }
    });

    for (const [name, entry] of Object.entries(project.sources)) {
      if (entry.type !== 'pinned' || !entry.fallback) continue;
      if (!known.has(entry.fallback)) {
        ctx.addIssue({
          code: 'custom',
          path: ['sources', name, 'fallback'],
          message: `Unknown fallback source "${entry.fallback}".`,
        });
      }
      if (entry.fallback === name) {
        ctx.addIssue({
          code: 'custom',
          path: ['sources', name, 'fallback'],
          message: 'A source cannot fall back to itself.',
        });
      }
    }
  });

export type Project = z.infer<typeof projectSchema>;
export type Section = Project['sections'][number];
export type LinkItem = z.infer<typeof linkItem>;
export type Social = z.infer<typeof social>;
export type SourceConfig = z.infer<typeof source>;
export type SourceMap = Project['sources'];
