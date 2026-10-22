# ohf-tree

Mobile-first link-in-bio pages for the Open Home Foundation and its projects —
the destination for "link in bio" on Instagram and anywhere else that allows
one URL.

One deploy serves every project: `/` is the foundation's own page, and each
project has a route (`/home-assistant`, `/esphome`, `/music-assistant`).

**Editing a page needs no tooling — see [docs/EDITING.md](docs/EDITING.md).**

## How it works

Each page is a YAML file in `src/content/projects/`. A page is an ordered list
of sections; a section is either hand-written links or a *source*, and a source
is a blog feed, a GitHub release list, a Mastodon account or a hand-written pin.
Sections ask for a source by name and render whatever comes back, so swapping a
pin for a live feed is a YAML edit rather than a code change.

`src/content/schema.ts` is the contract for all of that, and it is the first
place to look. It is enforced at build time, so an editing mistake fails the
pull request instead of reaching production.

### Freshness

A blog post often goes live minutes before the social promoting it, so a nightly
or hourly rebuild is too slow. Instead:

- Project routes render per request (`prerender = false`) and are **cached at
  the edge for 60 seconds** with `stale-while-revalidate` (`src/lib/cache.ts`).
  Visitors get HTML from cache at static-file speed; the cache refreshes in the
  background, so a new post appears within a minute unattended. The function
  runs about once a minute, not once per visitor.
- Each project site additionally **pings a Netlify build hook when it deploys**,
  which is the moment a post goes live, making the common case immediate.

The two are deliberately independent: the webhook makes publishing instant, and
the 60-second revalidation covers everything without a hook (Mastodon, releases,
pin expiry) and any webhook that silently stops firing. Remove every hook and
the page is still correct within a minute.

### When a feed is down

Feeds are resolved on the request path, so they are never allowed to hold up a
page. Each fetch has an ~800ms ceiling and degrades in order:

**live result → build-time snapshot → the section's curated fallback → section omitted.**

The snapshot is captured by `scripts/snapshot.mjs` at build time and bundled
with the function, so there is always something in memory with no network call.
A source is never a visible error and never an empty heading. The weekly
`feed-health` workflow is what complains about a permanently dead feed.

## Analytics

Not wired up yet, deliberately. Every outbound link renders through
`src/components/LinkTile.astro` and already carries `data-project`,
`data-section`, `data-source` and `data-label` — the event properties, named
now. Turning Plausible on means filling in `src/components/Analytics.astro` and
widening the CSP in `netlify.toml`.

## Local development

Requires Node >= 22.23.4 (see `.nvmrc`).

```sh
npm install
npm run dev      # http://localhost:4321
npm test         # feed parsing, pin fallback, timeouts, cycles
npx astro check  # types
npm run build
```

`npm run dev` and `npm run build` first run `scripts/snapshot.mjs`, which tries
every feed and warns about the ones it cannot reach. That is not a failure.

## Deployment

Netlify, with `netlify.toml` in this repo. The host is not hardcoded anywhere:
`SITE_URL` and `BASE_PATH` come from the environment, so `bio.ohf.to`,
`ohf.to/bio` and a per-project subdomain pointed at the same deploy are all
configuration rather than code changes.
