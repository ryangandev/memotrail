import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  devIndicators: false,
  distDir: process.env.MEMOTRAIL_NEXT_DIST_DIR ?? ".next",
  typescript: {
    tsconfigPath: process.env.MEMOTRAIL_NEXT_TSCONFIG ?? "tsconfig.json",
  },
  serverExternalPackages: [
    "@memotrail/media-runtime",
    "sharp",
    "libheif-js",
    "exifr",
  ],
  // Library replaced the separate search page and the Inbox, and tags
  // replaced Collections. Redirecting here, before any rendering, keeps old
  // links to one request instead of a rendered page that then navigates
  // again. Query values pass through to the destination.
  async redirects() {
    return [
      { source: "/search", destination: "/library", permanent: false },
      {
        source: "/inbox",
        has: [
          {
            type: "query",
            key: "entry",
            value: "(?<entry>[0-9a-fA-F-]{36})",
          },
        ],
        destination: "/items/:entry",
        permanent: false,
      },
      {
        source: "/inbox",
        destination: "/library?show=needs-organizing",
        permanent: false,
      },
      { source: "/collections/:path*", destination: "/tags", permanent: false },
      { source: "/people/:path*", destination: "/library", permanent: false },
      {
        source: "/settings/organization",
        destination: "/tags",
        permanent: false,
      },
    ];
  },
  outputFileTracingIncludes: {
    "/*": [
      "./node_modules/libheif-js/libheif-wasm/libheif-bundle.js",
      "./node_modules/libheif-js/wasm-bundle.js",
      "./node_modules/libheif-js/package.json",
    ],
  },
};

export default nextConfig;
