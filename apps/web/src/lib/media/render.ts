import { Worker } from "node:worker_threads";
// Keep Sharp's runtime and native dependencies visible to Next's deployment tracer.
// Decoding still runs only inside the bounded worker.
import "sharp";
import { createRequire } from "node:module";
import {
  MEDIA_MAX_BYTES,
  MEDIA_MAX_PIXELS,
  type MediaVariant,
} from "./contracts";
import { imageWorkerSource } from "./image-worker-source";
// Resolve real filesystem paths at runtime, not Turbopack's external module identifiers.
const runtimeRequire = createRequire(`${process.cwd()}/package.json`);
export type RenderedImage = {
  variant: MediaVariant;
  bytes: Buffer;
  width: number;
  height: number;
};
export function renderPhoto(
  bytes: Uint8Array,
  timeout = 25_000,
): Promise<RenderedImage[]> {
  if (!bytes.length || bytes.length > MEDIA_MAX_BYTES)
    return Promise.reject(new Error("Invalid image size"));
  return new Promise((resolve, reject) => {
    const worker = new Worker(imageWorkerSource, {
      eval: true,
      env: {},
      execArgv: [],
      resourceLimits: { maxOldGenerationSizeMb: 128 },
      workerData: {
        bytes,
        maxPixels: MEDIA_MAX_PIXELS,
        sharpPath: runtimeRequire.resolve("sharp"),
        heifPath: runtimeRequire.resolve("libheif-js/wasm-bundle"),
      },
    });
    let finished = false;
    const finish = (error?: Error, result?: RenderedImage[]) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      void worker.terminate();
      if (error) reject(error);
      else resolve(result!);
    };
    const timer = setTimeout(
      () => finish(new Error("Image processing timed out")),
      timeout,
    );
    worker.once("error", (error) =>
      finish(
        new Error(
          "code" in error && error.code === "MODULE_NOT_FOUND"
            ? "Image decoder unavailable"
            : "Image processing failed",
        ),
      ),
    );
    worker.once("exit", () => {
      if (!finished) finish(new Error("Image processing interrupted"));
    });
    worker.once("message", (message) => {
      if (
        message.error ||
        !Array.isArray(message.variants) ||
        message.variants.length !== 2
      )
        return finish(new Error("Invalid image"));
      const result: RenderedImage[] = message.variants.map(
        (v: RenderedImage) => ({ ...v, bytes: Buffer.from(v.bytes) }),
      );
      if (
        result.some((v) => !v.bytes.length || v.bytes.length > 8 * 1024 * 1024)
      )
        return finish(new Error("Preview too large"));
      finish(undefined, result);
    });
  });
}
