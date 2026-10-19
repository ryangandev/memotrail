import { Buffer } from "node:buffer";
import yazl from "yazl";

/** Test helper: builds a ZIP in memory from synthetic files. Never holds real data. */
export async function buildZip(
  files: Record<string, string | Buffer>,
  options: { mtime?: Date } = {},
): Promise<Buffer> {
  const zip = new yazl.ZipFile();
  for (const [name, content] of Object.entries(files)) {
    zip.addBuffer(
      typeof content === "string" ? Buffer.from(content, "utf8") : content,
      name,
      { mtime: options.mtime ?? new Date("2026-10-18T10:00:00Z") },
    );
  }
  zip.end();
  const chunks: Buffer[] = [];
  for await (const chunk of zip.outputStream) chunks.push(chunk as Buffer);
  return Buffer.concat(chunks);
}

/** A 1x1 PNG, so photo handling sees real image bytes. */
export const tinyPng = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=",
  "base64",
);

/** A JPEG signature followed by filler. Enough for type detection. */
export const tinyJpeg = Buffer.concat([
  Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]),
  Buffer.from("JFIF", "ascii"),
  Buffer.alloc(32),
]);
