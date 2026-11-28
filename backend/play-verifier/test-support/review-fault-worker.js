import worker from '../src/worker.js';

// Staging-only entry point for RA-12. The production entry point stays in src/.
export default {
  ...worker,
  async fetch(request, env) {
    const status = Number(env.REVIEW_REFRESH_TEST_STATUS);
    const reviewRequest = new URL(request.url).pathname === '/review' &&
      request.method === 'POST' && [429, 503].includes(status);
    if (!reviewRequest) return worker.fetch(request, env);

    const copy = request.clone();
    const response = await worker.fetch(request, env);
    // Preserve authentication failures and actual service failures. A successful
    // refresh has no persistent write; its signed grant is discarded here.
    if (response.status !== 200) {
      return response;
    }
    const body = await copy.json();
    if (body.action !== 'refresh') return response;
    const headers = {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store, private',
      'X-Content-Type-Options': 'nosniff',
      'X-YomiPalette-Test-Fault': `review-refresh-${status}`,
    };
    if (status === 429) headers['Retry-After'] = '60';
    return new Response(JSON.stringify({ status: 'unavailable' }), { status, headers });
  },
};
