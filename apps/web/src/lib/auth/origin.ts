export function requestOriginAllowed(
  request: Request,
  bearer: boolean,
  appURL?: string,
) {
  if (bearer) return true;
  const origin = request.headers.get("origin");
  // Proxies may normalize the internal hostname. Trust the configured public URL.
  return origin === new URL(appURL || request.url).origin;
}
