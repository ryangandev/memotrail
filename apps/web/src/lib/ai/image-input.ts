export type AIImage = { mediaType: "image/webp"; data: string };
export const AI_PHOTO_LIMIT = 12;
export const AI_PHOTO_BYTES = 1024 * 1024;
// Above the model's standard-tier 1,568-token image maximum, including block overhead.
export const AI_PHOTO_RESERVE = 2048;

export function imageContent(images: AIImage[]) {
  if (!Array.isArray(images) || images.length > AI_PHOTO_LIMIT)
    throw Error("Invalid AI images");
  return images.map((image) => {
    if (
      image.mediaType !== "image/webp" ||
      typeof image.data !== "string" ||
      image.data.length > Math.ceil(AI_PHOTO_BYTES / 3) * 4 ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(image.data)
    )
      throw Error("Invalid AI image");
    const bytes = Buffer.from(image.data, "base64");
    if (
      bytes.length < 12 ||
      bytes.length > AI_PHOTO_BYTES ||
      bytes.toString("base64") !== image.data ||
      bytes.toString("ascii", 0, 4) !== "RIFF" ||
      bytes.toString("ascii", 8, 12) !== "WEBP"
    )
      throw Error("Invalid AI image");
    return {
      type: "image" as const,
      source: {
        type: "base64" as const,
        media_type: image.mediaType,
        data: image.data,
      },
    };
  });
}
