import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  distDir: process.env.MEMOTRAIL_NEXT_DIST_DIR ?? ".next",
  serverExternalPackages: [
    "@memotrail/media-runtime",
    "sharp",
    "libheif-js",
    "exifr",
  ],
  outputFileTracingIncludes: {
    "/*": [
      "./node_modules/libheif-js/libheif-wasm/libheif-bundle.js",
      "./node_modules/libheif-js/wasm-bundle.js",
      "./node_modules/libheif-js/package.json",
    ],
  },
};

export default nextConfig;
