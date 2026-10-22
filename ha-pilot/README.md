# Bio page for home-assistant.io

The files for a link-in-bio page at `https://www.home-assistant.io/bio/`, built
natively in the site's Jekyll setup. Destined for `home-assistant/home-assistant.io`.

## Files that go into home-assistant.io (same paths)

| File | What it is |
| --- | --- |
| `source/_data/bio.yml` | The page. What comms edits. |
| `source/bio.html` | The `/bio/` route. |
| `source/_layouts/bio.html` | Standalone page — no site header, nav or footer. Keeps social meta and Plausible. |
| `source/_includes/bio/tile.html` | Every link renders here, with `data-*` attributes for analytics. |
| `source/_includes/bio/style.css` | Inlined stylesheet. |
| `plugins/bio.rb` | Validates `bio.yml` (a mistake fails the build, naming the line) and resolves sections. |

Everything else here is a test harness: `_config.yml`, the fixture posts, and the
stubbed `site/social_meta.html` and `site/plausible.html` (the real ones live in
home-assistant.io).

## How it works

- Sources are local: blog posts and release notes come from `site.posts`. No
  network at build time.
- A pin is a source type. While it has an item, it replaces the blog feed; once
  it's empty or `expires` passes, the page falls back to the latest post.
- `image: auto` reuses the site's own social-preview logic: a post's `og_image`,
  or the OHF Open Graph endpoint for anything else.
- `starts` / `ends` take effect at the next deploy on or after that date.

## Run it

Needs Ruby and Jekyll 4.4.1 (the version home-assistant.io pins).

```sh
gem install jekyll -v 4.4.1
ruby test/bio_test.rb   # validation, pins, scheduling, images
jekyll build            # renders public/bio/index.html
```
