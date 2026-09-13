import { expect, it } from "vitest";
import {
  AI_PHOTO_BYTES,
  AI_PHOTO_LIMIT,
  imageContent,
  type AIImage,
} from "./image-input";
const image: AIImage = {
  mediaType: "image/webp",
  data: Buffer.from("RIFF0000WEBPtest").toString("base64"),
};
it("builds inline image blocks without any public URL", () => {
  expect(imageContent([image])).toEqual([
    {
      type: "image",
      source: { type: "base64", media_type: "image/webp", data: image.data },
    },
  ]);
  expect(imageContent([])).toEqual([]);
});
it("limits the number of previews", () => {
  expect(imageContent(Array(AI_PHOTO_LIMIT).fill(image))).toHaveLength(
    AI_PHOTO_LIMIT,
  );
  expect(() => imageContent(Array(AI_PHOTO_LIMIT + 1).fill(image))).toThrow();
});
it.each([
  "https://example.com/photo.webp",
  "",
  "SGVsbG8=",
  image.data + "\n",
  "!!!!",
])("rejects invalid preview payload %s", (data) => {
  expect(() => imageContent([{ ...image, data }])).toThrow();
});
it("refuses oversized data and original formats", () => {
  expect(() =>
    imageContent([
      { ...image, data: Buffer.alloc(AI_PHOTO_BYTES + 1).toString("base64") },
    ]),
  ).toThrow();
  expect(() =>
    imageContent([{ ...image, mediaType: "image/jpeg" } as unknown as AIImage]),
  ).toThrow();
});
