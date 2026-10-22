import type { FetchOptions } from './types.ts';

/**
 * A fetch that always loses to the clock. Feeds are resolved on the request
 * path, so a hanging feed must cost us its timeout and nothing more.
 */
export async function fetchText(url: string, { timeoutMs }: FetchOptions): Promise<string> {
  const response = await fetch(url, {
    signal: AbortSignal.timeout(timeoutMs),
    headers: { 'user-agent': 'ohf-tree (+https://www.openhomefoundation.org)' },
  });

  if (!response.ok) {
    throw new Error(`${url} responded ${response.status}`);
  }

  return response.text();
}

export async function fetchJson<T>(url: string, options: FetchOptions): Promise<T> {
  return JSON.parse(await fetchText(url, options)) as T;
}
