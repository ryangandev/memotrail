import { describe, expect, it } from "vitest";
import sharp from "sharp";
import { renderPhoto } from "./render";
import { readFileSync } from "node:fs";
describe("private photo derivatives", () => {
  it("preserves original bytes, rotates display pixels, strips metadata, and creates both bounded variants", async () => {
    const original = await sharp({
      create: { width: 2400, height: 1200, channels: 3, background: "#2e604f" },
    })
      .jpeg()
      .withMetadata({ orientation: 6 })
      .withExif({ IFD0: { Artist: "Synthetic MemoTrail fixture" } })
      .toBuffer();
    const unchanged = Buffer.from(original);
    const result = await renderPhoto(original);
    expect(original.equals(unchanged)).toBe(true);
    expect(result.map((v) => [v.variant, v.width, v.height])).toEqual([
      ["display", 800, 1600],
      ["thumbnail", 200, 400],
    ]);
    for (const image of result) {
      const metadata = await sharp(image.bytes).metadata();
      expect(metadata.format).toBe("webp");
      expect(metadata.exif).toBeUndefined();
      expect(metadata.orientation).toBeUndefined();
    }
  });
  it("preserves transparency and does not enlarge a small image", async () => {
    const original = await sharp({
      create: {
        width: 12,
        height: 20,
        channels: 4,
        background: { r: 30, g: 80, b: 50, alpha: 0.5 },
      },
    })
      .png()
      .toBuffer();
    for (const image of await renderPhoto(original)) {
      const metadata = await sharp(image.bytes).metadata();
      expect([metadata.width, metadata.height]).toEqual([12, 20]);
      expect(metadata.hasAlpha).toBe(true);
    }
  });
  it("rejects invalid bytes, unsupported formats, oversized input and decoder timeouts", async () => {
    await expect(renderPhoto(Buffer.from("not an image"))).rejects.toThrow();
    await expect(
      renderPhoto(Buffer.alloc(50 * 1024 * 1024 + 1)),
    ).rejects.toThrow();
    await expect(
      renderPhoto(Buffer.from('<svg width="10" height="10"></svg>')),
    ).rejects.toThrow();
    const original = await sharp({
      create: { width: 12, height: 20, channels: 3, background: "white" },
    })
      .png()
      .toBuffer();
    await expect(renderPhoto(original, 1)).rejects.toThrow("timed out");
  });
  it("decodes an actual HEIC original into portable WebP previews", async () => {
    const bytes = Buffer.from(
      readFileSync(
        new URL("./fixtures/synthetic.heic.base64", import.meta.url),
        "utf8",
      ).trim(),
      "base64",
    );
    const result = await renderPhoto(bytes);
    expect(result).toHaveLength(2);
    for (const image of result) {
      const metadata = await sharp(image.bytes).metadata();
      expect(metadata.format).toBe("webp");
      expect([metadata.width, metadata.height]).toEqual([120, 80]);
    }
  });
});
