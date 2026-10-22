import { fetchJson } from './fetch.ts';
import type { FeedItem, FetchOptions } from './types.ts';

interface Release {
  name: string | null;
  tag_name: string;
  html_url: string;
  published_at: string | null;
  draft: boolean;
  prerelease: boolean;
}

/**
 * Unauthenticated at request time; the 60s edge cache keeps us far below the
 * rate limit. GITHUB_TOKEN is used when present (CI, snapshot builds).
 */
export async function loadGithubReleases(
  config: { repo: string; includePrereleases: boolean },
  options: FetchOptions,
): Promise<FeedItem[]> {
  const releases = await fetchJson<Release[]>(
    `https://api.github.com/repos/${config.repo}/releases?per_page=10`,
    options,
  );

  return releases
    .filter((release) => !release.draft && (config.includePrereleases || !release.prerelease))
    .map((release) => ({
      title: release.name?.trim() || release.tag_name,
      url: release.html_url,
      date: release.published_at ? new Date(release.published_at) : undefined,
    }));
}
