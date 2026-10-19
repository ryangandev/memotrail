import { describe, expect, it } from "vitest";
import type { FirstTimeAttachment, FirstTimeEntry } from "./first-times";
import {
  firstTimeExcerpt,
  firstTimePhotos,
  firstTimeRowDateLabel,
  firstTimeRowDetails,
} from "./first-times-presentation";

function entry(overrides: Partial<FirstTimeEntry> = {}): FirstTimeEntry {
  return {
    attachments: [],
    body: "",
    datePrecision: "day",
    id: "first-1",
    isChapter: false,
    location: null,
    occurredEnd: null,
    occurredLabel: null,
    occurredStart: "2026-10-14T16:00:00Z",
    occurredTimezone: "America/New_York",
    revision: 1,
    tagNames: [],
    title: "First time cooking for twelve",
    untitled: false,
    updatedAt: "2026-10-14T16:00:00Z",
    ...overrides,
  };
}

function attachment(
  id: string,
  variant: FirstTimeAttachment["variant"],
): FirstTimeAttachment {
  return {
    bucketId: "entry-media",
    byteSize: 1,
    createdAt: "2026-10-14T16:00:00Z",
    id,
    imageUrl: null,
    mimeType: "image/jpeg",
    objectPath: `owner/${id}.jpg`,
    originalFilename: null,
    parentAttachmentId: variant === "original" ? null : "photo-1",
    pixelHeight: null,
    pixelWidth: null,
    variant,
  };
}

describe("firstTimeRowDateLabel", () => {
  it("reads at the precision the First Time was recorded", () => {
    expect(firstTimeRowDateLabel(entry())).toBe("Oct 14, 2026");
    expect(
      firstTimeRowDateLabel(
        entry({
          datePrecision: "month",
          occurredStart: "2024-10-01T16:00:00Z",
        }),
      ),
    ).toBe("Oct 2024");
    expect(
      firstTimeRowDateLabel(
        entry({ datePrecision: "approximate", occurredLabel: "Fall 2025" }),
      ),
    ).toBe("Fall 2025");
  });

  it("leaves out the time of an exact moment", () => {
    expect(
      firstTimeRowDateLabel(
        entry({
          datePrecision: "exact",
          occurredStart: "2025-11-14T19:30:00Z",
        }),
      ),
    ).toBe("Nov 14, 2025");
  });

  it("reads a First Time that is also a Chapter as its span", () => {
    expect(
      firstTimeRowDateLabel(
        entry({
          datePrecision: "month",
          isChapter: true,
          occurredEnd: "2023-06-30T16:00:00Z",
          occurredStart: "2021-09-01T16:00:00Z",
        }),
      ),
    ).toBe("Sep 2021 - Jun 2023");
    expect(
      firstTimeRowDateLabel(
        entry({
          isChapter: true,
          occurredEnd: "2023-06-30T16:00:00Z",
          occurredStart: "2021-09-01T16:00:00Z",
        }),
      ),
    ).toBe("Sep 2021 - Jun 2023");
    expect(
      firstTimeRowDateLabel(
        entry({ isChapter: true, occurredStart: "2021-09-01T16:00:00Z" }),
      ),
    ).toBe("Since Sep 2021");
  });

  it("says Undated when there is no date to show", () => {
    expect(
      firstTimeRowDateLabel(
        entry({ datePrecision: "unknown", occurredStart: null }),
      ),
    ).toBe("Undated");
  });

  it("is empty for an untitled First Time, whose title is already its date", () => {
    expect(
      firstTimeRowDateLabel(entry({ title: "October 2024", untitled: true })),
    ).toBeNull();
  });
});

describe("firstTimeRowDetails", () => {
  it("names the city, counts saved photos once each, and lists tags", () => {
    expect(
      firstTimeRowDetails(
        entry({
          attachments: [
            attachment("photo-1", "original"),
            attachment("photo-1-display", "display"),
            attachment("photo-1-thumbnail", "thumbnail"),
            attachment("photo-2", "original"),
          ],
          location: {
            address: "10 Pine Street",
            city: "Philadelphia",
            country: "United States",
            countryCode: "us",
            formattedAddress: "10 Pine Street, Philadelphia, PA, United States",
            id: "location-1",
            kind: "existing",
            latitude: 39.94,
            longitude: -75.14,
            postalCode: null,
            region: "PA",
            resultType: null,
            revision: 1,
            timezone: null,
          },
          tagNames: ["cooking", "friends"],
        }),
      ),
    ).toEqual(["Philadelphia", "2 photos", "#cooking #friends"]);
  });

  it("is empty when there is nothing more to say", () => {
    expect(firstTimeRowDetails(entry())).toEqual([]);
  });
});

describe("firstTimePhotos", () => {
  it("keeps one attachment per saved photo", () => {
    expect(
      firstTimePhotos(
        entry({
          attachments: [
            attachment("photo-1", "original"),
            attachment("photo-1-display", "display"),
          ],
        }),
      ).map((photo) => photo.id),
    ).toEqual(["photo-1"]);
  });
});

describe("firstTimeExcerpt", () => {
  it("folds line breaks into one line", () => {
    expect(firstTimeExcerpt("  Two lasagnas.\n\nNot enough chairs. ")).toBe(
      "Two lasagnas. Not enough chairs.",
    );
  });
});
