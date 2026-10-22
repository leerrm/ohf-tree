import assert from 'node:assert/strict';
import { createServer, type Server } from 'node:http';
import { after, before, describe, it } from 'node:test';
import { parseFeed } from '../src/feeds/parse-feed.ts';
import { resolveSource } from '../src/feeds/resolve.ts';
import type { SourceMap } from '../src/content/schema.ts';

const ATOM = `<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <title>2026.11: the one with the thing</title>
    <link rel="alternate" href="https://example.test/blog/2026/11/05/release/"/>
    <published>2026-11-05T10:00:00Z</published>
    <summary>&lt;p&gt;Loads of &lt;b&gt;new&lt;/b&gt; stuff.&lt;/p&gt;</summary>
  </entry>
  <entry>
    <title>An older post</title>
    <link rel="alternate" href="https://example.test/blog/2026/10/01/older/"/>
    <published>2026-10-01T10:00:00Z</published>
  </entry>
</feed>`;

const RSS = `<?xml version="1.0"?>
<rss version="2.0"><channel>
  <item>
    <title>Toot about a thing</title>
    <link>https://example.test/@ohf/1</link>
    <pubDate>Tue, 04 Nov 2026 09:00:00 +0000</pubDate>
    <description>&lt;p&gt;Hello fediverse&lt;/p&gt;</description>
  </item>
</channel></rss>`;

describe('parseFeed', () => {
  it('reads Atom entries newest-first with HTML stripped from summaries', () => {
    const items = parseFeed(ATOM);
    assert.equal(items.length, 2);
    assert.equal(items[0]?.title, '2026.11: the one with the thing');
    assert.equal(items[0]?.url, 'https://example.test/blog/2026/11/05/release/');
    assert.equal(items[0]?.excerpt, 'Loads of new stuff.');
  });

  it('reads RSS 2.0 items', () => {
    const items = parseFeed(RSS);
    assert.equal(items[0]?.url, 'https://example.test/@ohf/1');
    assert.equal(items[0]?.excerpt, 'Hello fediverse');
  });

  it('returns nothing rather than throwing on junk', () => {
    assert.deepEqual(parseFeed('<html>not a feed</html>'), []);
  });
});

describe('resolveSource', () => {
  let server: Server;
  let origin = '';
  /** Held open to prove a hanging feed cannot hold up a page. */
  let hangingResponses: Array<() => void> = [];

  before(async () => {
    server = createServer((request, response) => {
      if (request.url === '/atom.xml') {
        response.writeHead(200, { 'content-type': 'application/atom+xml' });
        response.end(ATOM);
        return;
      }
      if (request.url === '/hangs') {
        hangingResponses.push(() => response.end());
        return; // never responds
      }
      response.writeHead(500).end('nope');
    });
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
    const address = server.address();
    origin = `http://127.0.0.1:${typeof address === 'object' && address ? address.port : 0}`;
  });

  after(async () => {
    for (const end of hangingResponses) end();
    await new Promise((resolve) => server.close(resolve));
  });

  const context = (sources: SourceMap, now = new Date('2026-11-06T00:00:00Z')) => ({
    sources,
    snapshotPrefix: 'test',
    now,
  });

  it('resolves a live feed', async () => {
    const items = await resolveSource(
      'blog',
      context({ blog: { type: 'rss', url: `${origin}/atom.xml` } }),
    );
    assert.equal(items.length, 2);
    assert.equal(items[0]?.title, '2026.11: the one with the thing');
  });

  it('serves an active pin ahead of the feed behind it', async () => {
    const items = await resolveSource(
      'latest',
      context({
        blog: { type: 'rss', url: `${origin}/atom.xml` },
        latest: {
          type: 'pinned',
          items: [{ title: 'Pinned launch', url: 'https://example.test/launch' }],
          fallback: 'blog',
        },
      }),
    );
    assert.equal(items.length, 1);
    assert.equal(items[0]?.title, 'Pinned launch');
  });

  it('falls back to the live feed once the pin has expired', async () => {
    const items = await resolveSource(
      'latest',
      context({
        blog: { type: 'rss', url: `${origin}/atom.xml` },
        latest: {
          type: 'pinned',
          items: [
            {
              title: 'Pinned launch',
              url: 'https://example.test/launch',
              expires: new Date('2026-11-01T00:00:00Z'),
            },
          ],
          fallback: 'blog',
        },
      }),
    );
    assert.equal(items[0]?.title, '2026.11: the one with the thing');
  });

  it('returns nothing, not an error, when a source is down', async () => {
    const warnings: string[] = [];
    const items = await resolveSource('blog', {
      ...context({ blog: { type: 'rss', url: `${origin}/boom` } }),
      onWarn: (message) => warnings.push(message),
    });
    assert.deepEqual(items, []);
    assert.equal(warnings.length, 1);
  });

  it('gives up on a hanging feed within its timeout', async () => {
    const started = Date.now();
    const items = await resolveSource('blog', {
      ...context({ blog: { type: 'rss', url: `${origin}/hangs` } }),
      timeoutMs: 150,
    });
    assert.deepEqual(items, []);
    assert.ok(Date.now() - started < 1000, 'should abort well before a visitor notices');
  });

  it('does not loop on a fallback cycle', async () => {
    const items = await resolveSource(
      'a',
      context({
        a: { type: 'pinned', items: [], fallback: 'b' },
        b: { type: 'pinned', items: [], fallback: 'a' },
      }),
    );
    assert.deepEqual(items, []);
  });
});
