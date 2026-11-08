/**
 * Cloudflare Workers Rate Limiting API is approximate and location-scoped.
 * These checks mitigate request floods; they do not authenticate purchasers.
 * Do not trust client-provided X-Forwarded-For headers.
 */
function requireLimiter(value) {
  if (!value || typeof value.limit !== 'function') {
    throw new Error('Verification rate limiting is not configured.');
  }
  return value;
}

export async function allowVerifyIp(env, request) {
  const ip = request.headers.get('CF-Connecting-IP');
  // Cloudflare sets CF-Connecting-IP on requests at its edge. Unknown or
  // malformed values share a bounded bucket instead of bypassing the limit.
  const key = ip && /^[0-9a-fA-F:.]{3,45}$/.test(ip)
    ? `ip:${ip}`
    : 'ip:unavailable';
  const response = await requireLimiter(env?.VERIFY_IP_RATE_LIMIT).limit({ key });
  if (typeof response?.success !== 'boolean') {
    throw new Error('Verification rate limiting returned an invalid response.');
  }
  return response.success;
}

export async function allowVerifyToken(env, tokenSha256) {
  if (!/^[0-9a-f]{64}$/.test(tokenSha256)) {
    throw new Error('Invalid purchase-token digest.');
  }
  // Token is *never* used raw as the limiter key or written to logs.
  const response = await requireLimiter(env?.VERIFY_TOKEN_RATE_LIMIT)
    .limit({ key: `token:${tokenSha256}` });
  if (typeof response?.success !== 'boolean') {
    throw new Error('Verification rate limiting returned an invalid response.');
  }
  return response.success;
}
