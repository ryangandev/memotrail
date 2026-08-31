const trustedRelativePathBase = new URL("https://memotrail.invalid");

export function safeRelativePath(value: string | null) {
  if (!value || !value.startsWith("/") || value.includes("\\")) {
    return "/";
  }

  try {
    const target = new URL(value, trustedRelativePathBase);

    if (target.origin !== trustedRelativePathBase.origin) {
      return "/";
    }

    return `${target.pathname}${target.search}${target.hash}`;
  } catch {
    return "/";
  }
}

export function applicationOrigin(
  requestUrl: URL,
  environment = process.env.NODE_ENV,
  configuredUrl = process.env.NEXT_PUBLIC_APP_URL,
) {
  if (environment !== "production") {
    return requestUrl.origin;
  }

  const configuredUrlValue = configuredUrl?.trim();

  if (!configuredUrlValue) {
    return requestUrl.origin;
  }

  try {
    const configuredOrigin = new URL(configuredUrlValue);

    if (!["http:", "https:"].includes(configuredOrigin.protocol)) {
      return requestUrl.origin;
    }

    return configuredOrigin.origin;
  } catch {
    return requestUrl.origin;
  }
}
