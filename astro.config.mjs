// @ts-check
import { defineConfig } from 'astro/config';
import netlify from '@astrojs/netlify';

// The deployed host is not fixed yet (bio.ohf.to, ohf.to/bio, a per-project
// subdomain...), so it comes from the environment and never from source.
const site = process.env.SITE_URL ?? 'http://localhost:4321';
const base = process.env.BASE_PATH ?? '/';

export default defineConfig({
  site,
  base,
  trailingSlash: 'ignore',
  // Pages are static by default; the project routes opt out so feeds stay fresh.
  output: 'static',
  adapter: netlify({
    // We only ever serve local SVG avatars, so the remote image endpoint is dead
    // weight — and leaving it on widens image.remotePatterns (GHSA advisory on
    // @astrojs/netlify >= 6.6.0).
    imageCDN: false,
  }),
  image: {
    remotePatterns: [],
  },
  build: {
    inlineStylesheets: 'always',
  },
  devToolbar: {
    enabled: false,
  },
});
