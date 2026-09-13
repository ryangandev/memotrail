import type { NextConfig } from "next";

const nextConfig: NextConfig = {
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
