import { describe, expect, it } from "vitest";
import {
  parseCaptureExtractionReference,
  pendingCaptureReference,
} from "./capture-extraction-input";

describe("Capture extraction reference", () => {
  it("accepts one current Capture identity", () => {
    expect(
      parseCaptureExtractionReference({
        id: "98400000-0000-4000-8000-000000000001",
        revision: 3,
      }),
    ).toEqual({
      id: "98400000-0000-4000-8000-000000000001",
      revision: 3,
    });
  });

  it.each([
    null,
    {},
    { id: "bad", revision: 1 },
    { id: "98400000-0000-4000-8000-000000000001", revision: 0 },
    { id: "98400000-0000-4000-8000-000000000001", revision: 1.5 },
  ])("rejects an invalid or stale reference: %j", (value) => {
    expect(parseCaptureExtractionReference(value)).toBeNull();
  });
});

describe("Pending Capture handoff", () => {
  const capture = {
    id: "98400000-0000-4000-8000-000000000001",
    revision: 3,
    title: "Learn to sail",
  };

  it("sends only the Capture identity while the record is being created", () => {
    expect(pendingCaptureReference(capture, null)).toEqual({
      id: "98400000-0000-4000-8000-000000000001",
      revision: 3,
    });
  });

  it("stops handing off the Capture once its record exists", () => {
    expect(
      pendingCaptureReference(capture, "98400000-0000-4000-8000-000000000002"),
    ).toBeNull();
    expect(pendingCaptureReference(null, null)).toBeNull();
  });
});
