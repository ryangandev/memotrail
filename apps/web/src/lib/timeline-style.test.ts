import { describe, expect, it } from "vitest";
import {
  parseTimelineStyle,
  storedTimelineStyle,
  timelineStyleCookieValue,
} from "./timeline-style";

describe("Timeline style preference", () => {
  it("defaults to the current Timeline for missing or invalid values", () => {
    expect(storedTimelineStyle(undefined, "owner-a")).toBe("classic");
    expect(storedTimelineStyle("owner-a:other", "owner-a")).toBe("classic");
    expect(parseTimelineStyle("other")).toBeNull();
  });

  it("keeps a browser preference scoped to the signed-in owner", () => {
    const value = timelineStyleCookieValue("owner-a", "sticky-year");
    expect(storedTimelineStyle(value, "owner-a")).toBe("sticky-year");
    expect(storedTimelineStyle(value, "owner-b")).toBe("classic");
  });
});
