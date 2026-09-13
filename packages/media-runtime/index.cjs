// Kept external to Next: Node resolves these relative to this package at runtime.
// Static requires also let the deployment tracer follow native transitive dependencies.
require("sharp");
require("exifr");
exports.decoderPaths = () => ({
  sharpPath: require.resolve("sharp"),
  exifrPath: require.resolve("exifr"),
  heifPath: require.resolve("libheif-js/wasm-bundle"),
});
