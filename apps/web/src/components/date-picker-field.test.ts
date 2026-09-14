import { describe, expect, it } from "vitest";
import { formatNumericDate } from "@/components/date-picker-field";

describe("formatNumericDate", () => {
  it("accepts only digits and inserts day separators", () => {
    expect(formatNumericDate("20ab17/07-08", "day")).toBe("2017-07-08");
    expect(formatNumericDate("201707081234", "day")).toBe("2017-07-08");
  });

  it("formats partial month and year input without inventing digits", () => {
    expect(formatNumericDate("20170", "month")).toBe("2017-0");
    expect(formatNumericDate("201707", "month")).toBe("2017-07");
    expect(formatNumericDate("20179", "year")).toBe("2017");
  });
});
