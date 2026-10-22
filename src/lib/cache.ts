/**
 * The freshness model in one place.
 *
 * Netlify-CDN-Cache-Control governs the edge cache: visitors are served HTML
 * from cache (as fast as a static file) while it revalidates in the background
 * every 60 seconds, so new feed items appear within a minute with nobody doing
 * anything. Cache-Control keeps browsers from holding their own stale copy, so
 * a reader who taps the bio link twice does not see yesterday's post.
 */
export function cacheAtEdge(headers: Headers, maxAgeSeconds = 60): void {
  headers.set(
    'Netlify-CDN-Cache-Control',
    `public, max-age=${maxAgeSeconds}, stale-while-revalidate=300`,
  );
  headers.set('Cache-Control', 'public, max-age=0, must-revalidate');
}
