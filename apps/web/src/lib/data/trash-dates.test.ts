import { describe, expect, it } from "vitest";
import { trashDate } from "./trash-dates";

describe("Trash dates", () => {
  const removedAt = "2026-11-01T03:30:00.000Z";

  it("shows the same calendar day wherever the page renders", () => {
    // The server and the browser format the same instant in different zones.
    for (const zone of ["America/Los_Angeles", "Asia/Tokyo"]) {
      const previous = process.env.TZ;
      process.env.TZ = zone;
      try {
        expect(trashDate(removedAt, "America/New_York")).toBe("Oct 31, 2026");
        expect(trashDate(removedAt, "Asia/Kathmandu")).toBe("Nov 1, 2026");
      } finally {
        if (previous === undefined) delete process.env.TZ;
        else process.env.TZ = previous;
      }
    }
  });

  it("falls back to UTC for a time zone it does not know", () => {
    expect(trashDate(removedAt, "Not/AZone")).toBe("Nov 1, 2026");
  });
});
