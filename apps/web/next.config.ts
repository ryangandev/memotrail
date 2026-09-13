import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  serverExternalPackages: ["sharp", "libheif-js"],
  outputFileTracingIncludes: {
    "/api/media/image": [
      "./node_modules/libheif-js/libheif-wasm/libheif-bundle.js",
      "./node_modules/libheif-js/wasm-bundle.js",
      "./node_modules/libheif-js/package.json",
    ],
  },
};

export default nextConfig;
