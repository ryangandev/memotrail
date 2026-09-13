import { describe, it, expect } from "vitest";
import sharp from "sharp";
import { readFileSync } from "node:fs";
import {
  normalizePhotoMetadata,
  photoCalendarDateDraft,
} from "./photo-metadata";
import { readPhotoMetadata } from "./metadata-worker";
import { resolveOccurrenceDraft } from "@/lib/data/occurrence";

describe("camera metadata suggestions", () => {
  it("preserves camera wall time and subsecond text without inventing a timezone", () => {
    const value = normalizePhotoMetadata({
      DateTimeOriginal: "2017:07:08 00:30:20",
      SubSecTimeOriginal: "123456",
    });
    expect(value).toEqual({
      capturedLocal: "2017-07-08T00:30:20.123456",
      calendarDate: "2017-07-08",
      offset: null,
      latitude: null,
      longitude: null,
    });
    expect(
      normalizePhotoMetadata({
        DateTimeOriginal: "2017:07:08 00:30:20",
        OffsetTimeOriginal: "+05:30",
      }).offset,
    ).toBe("+05:30");
  });
  it("rejects impossible dates, malformed offsets, partial GPS and out of range coordinates", () => {
    for (const date of [
      "2017:02:29 12:00:00",
      "2020:02:30 12:00:00",
      "0000:01:01 00:00:00",
      "2017:07:08 24:00:00",
      "unknown",
    ]) {
      expect(
        normalizePhotoMetadata({ DateTimeOriginal: date }).calendarDate,
      ).toBeNull();
    }
    for (const offset of ["+15:00", "-14:01", "+03:60", "+5:30"]) {
      expect(
        normalizePhotoMetadata({
          DateTimeOriginal: "2020:02:29 12:00:00",
          OffsetTimeOriginal: offset,
        }).offset,
      ).toBeNull();
    }
    for (const latitude of [
      [91, 0, 0],
      [20, 60, 0],
      [20, 0, 60],
      [-1, 0, 0],
      [NaN, 0, 0],
    ]) {
      expect(
        normalizePhotoMetadata({
          GPSLatitude: latitude,
          GPSLatitudeRef: "N",
          GPSLongitude: [70, 0, 0],
          GPSLongitudeRef: "E",
        }).latitude,
      ).toBeNull();
    }
    expect(
      normalizePhotoMetadata({ GPSLatitude: [0, 0, 0], GPSLatitudeRef: "N" })
        .latitude,
    ).toBeNull();
    expect(
      normalizePhotoMetadata({
        GPSLatitude: [0, 0, 0],
        GPSLatitudeRef: "S",
        GPSLongitude: [0, 0, 0],
        GPSLongitudeRef: "W",
      }).latitude,
    ).toBe(-0);
    expect(
      normalizePhotoMetadata({ ModifyDate: "2017:07:08 12:00:00" })
        .calendarDate,
    ).toBeNull();
  });
  it("only changes the explicit date draft while preserving its chosen timezone", () => {
    const previous = {
      precision: "range" as const,
      start: "2020-01-01",
      end: "2020-02-01",
      label: "Old range",
      timezone: "Pacific/Kiritimati",
    };
    const draft = photoCalendarDateDraft("2017-07-08", previous);
    expect(previous.start).toBe("2020-01-01");
    expect(draft).toEqual({
      precision: "day",
      start: "2017-07-08",
      end: "",
      label: "",
      timezone: "Pacific/Kiritimati",
    });
    expect(resolveOccurrenceDraft(draft).value?.occurredAt).toBe(
      "2017-07-07T22:00:00.000Z",
    );
    expect(() => photoCalendarDateDraft("2017-02-29", previous)).toThrow();
  });
  it("reads real JPEG, PNG and WebP EXIF using a bounded TIFF parser", async () => {
    const pipeline = sharp({
      create: { width: 20, height: 20, channels: 3, background: "green" },
    }).withExif({
      IFD0: { Artist: "Private artist not returned" },
      IFD2: {
        DateTimeOriginal: "2017:07:08 12:34:56",
        OffsetTimeOriginal: "-04:00",
        SubSecTimeOriginal: "123",
      },
      IFD3: {
        GPSLatitudeRef: "N",
        GPSLatitude: "39/1 57/1 0/1",
        GPSLongitudeRef: "W",
        GPSLongitude: "75/1 10/1 0/1",
      },
    });
    for (const format of ["jpeg", "png", "webp"] as const) {
      const bytes = await pipeline.clone().toFormat(format).toBuffer();
      const unchanged = Buffer.from(bytes);
      const value = await readPhotoMetadata(bytes);
      expect(value.calendarDate).toBe("2017-07-08");
      expect(value.offset).toBe("-04:00");
      expect(value.latitude).toBeCloseTo(39.95);
      expect(value.longitude).toBeCloseTo(-75.166667);
      expect(bytes.equals(unchanged)).toBe(true);
      expect(JSON.stringify(value)).not.toContain("Private artist");
    }
  });
  it("reads a HEIC container without decoding its pixels, and handles absent metadata", async () => {
    const cameraHEIC = Buffer.from(
      readFileSync(
        new URL("./fixtures/camera-metadata.heic.base64", import.meta.url),
        "utf8",
      ).trim(),
      "base64",
    );
    const camera = await readPhotoMetadata(cameraHEIC);
    expect(camera.calendarDate).toBe("2017-07-08");
    expect(camera.latitude).toBeCloseTo(39.95);
    expect(camera.longitude).toBeCloseTo(-75.166667);
    const heic = Buffer.from(
      readFileSync(
        new URL("./fixtures/synthetic.heic.base64", import.meta.url),
        "utf8",
      ).trim(),
      "base64",
    );
    expect((await readPhotoMetadata(heic)).calendarDate).toBeNull();
    const png = await sharp({
      create: { width: 1, height: 1, channels: 3, background: "white" },
    })
      .png()
      .toBuffer();
    expect((await readPhotoMetadata(png)).latitude).toBeNull();
    await expect(
      readPhotoMetadata(Buffer.from("not a photo")),
    ).rejects.toThrow();
    await expect(
      readPhotoMetadata(Buffer.from('<svg width="10" height="10"></svg>')),
    ).rejects.toThrow();
    await expect(readPhotoMetadata(png, 1)).rejects.toThrow();
  });
});
