import { describe, expect, it } from "vitest";
import { trashDate, trashRetention } from "./trash-dates";

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

  it("counts the days left from the time the page was rendered", () => {
    const expiresAt = "2026-11-30T12:00:00.000Z";

    expect(trashRetention(expiresAt, "2026-11-01T12:00:00.000Z")).toBe(
      "29 days to restore · through",
    );
    expect(trashRetention(expiresAt, "2026-11-29T13:00:00.000Z")).toBe(
      "1 day to restore · through",
    );
    expect(trashRetention(expiresAt, expiresAt)).toBe(
      "Eligible for cleanup since",
    );
    expect(trashRetention(expiresAt, "2026-12-15T00:00:00.000Z")).toBe(
      "Eligible for cleanup since",
    );
  });
});
