# Editing a page

You don't need to install anything. Every page is one file you can edit in the
browser, and GitHub will show you a preview of your change before it goes live.

## Where the pages are

| Page | File |
| --- | --- |
| Open Home Foundation | `src/content/projects/ohf.yaml` |
| Home Assistant | `src/content/projects/home-assistant.yaml` |
| ESPHome | `src/content/projects/esphome.yaml` |
| Music Assistant | `src/content/projects/music-assistant.yaml` |

## Making a change

1. Open the file on GitHub and click the pencil icon.
2. Make your edit.
3. At the bottom, choose **Create a new branch for this commit** and click
   **Propose changes**.
4. On the pull request, wait about a minute for the **Deploy Preview** link,
   then open it on your phone. That is exactly what visitors will see.
5. Ask someone to merge it. It is live about 40 seconds later.

If you make a mistake — a missing link, a date typed the wrong way round — the
checks on the pull request go red and tell you which line is wrong. Nothing
broken can reach the live page.

## Adding a link

Find the `- type: links` block you want it in and add an item:

```yaml
  - type: links
    title: Get involved
    items:
      - label: Vote in the 2026 survey
        url: https://www.openhomefoundation.org/survey/
        note: Closes 30 November        # optional second line
        featured: true                  # optional — the accent-coloured tile
```

Keep `featured: true` for one tile at most. If everything is emphasised,
nothing is.

## Making a link appear and disappear on a schedule

Add `starts` and/or `ends`. Outside that window the tile is not on the page at
all, so you can queue a campaign in advance and forget about it.

```yaml
      - label: Join us at the release party
        url: https://www.home-assistant.io/release-party/
        starts: 2026-12-01
        ends: 2026-12-04
```

Dates are `YYYY-MM-DD`. Both are optional and take effect within a minute, with
no deploy needed.

## Pinning a specific post

Normally the "Latest from the blog" tile fills itself from the blog feed, within
a minute of a post going live. When the timing has to be exact — a launch, an
embargo, a post you want up *before* the social goes out — pin it.

Find the `pinned` source in the same file and add the post:

```yaml
  ha-latest:
    type: pinned
    items:
      - title: 2026.11 is here
        url: https://www.home-assistant.io/blog/2026/11/05/release-202611/
        expires: 2026-11-12       # optional — hands back to the blog feed
    fallback: ha-blog
```

While a pin is there, the page shows it instead of the feed. Remove it (or let
`expires` pass) and the page goes back to the latest blog post on its own, so
there is nothing to remember to undo.

## Changing what sections appear, and in what order

The `sections` list *is* the page, top to bottom. Move a block to move the
section. Delete a block and the section is gone. There is no hidden state and
nothing else to update.

## What you cannot break

- A link to a source that doesn't exist, a malformed date, a missing `url`:
  the checks fail and tell you where.
- A blog or GitHub outage: the page drops that section rather than showing an
  error or an empty heading. It comes back on its own.
