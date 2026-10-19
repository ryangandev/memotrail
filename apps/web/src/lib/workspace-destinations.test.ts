import { describe, expect, it } from "vitest";
import {
  destinationForEntry,
  destinationForPathname,
  moreDestinations,
  sidebarGroups,
  tabBarDestinations,
} from "./workspace-destinations";

const labels = (links: readonly { label: string }[]) =>
  links.map((link) => link.label);

describe("workspace destinations", () => {
  it("orders the sidebar in three groups with the tools at the foot", () => {
    expect(sidebarGroups.map(labels)).toEqual([
      ["Dashboard", "Timeline", "Library"],
      ["First Times", "Reviews", "Tags"],
      ["Import", "Trash", "Settings"],
    ]);
  });

  it("keeps every destination reachable on a phone exactly once", () => {
    expect(labels(tabBarDestinations)).toEqual([
      "Dashboard",
      "Timeline",
      "Library",
    ]);
    expect(labels(moreDestinations)).toEqual([
      "First Times",
      "Reviews",
      "Tags",
      "Import",
      "Trash",
      "Settings",
    ]);
    expect(
      [...labels(tabBarDestinations), ...labels(moreDestinations)].sort(),
    ).toEqual(sidebarGroups.flatMap(labels).sort());
  });

  it.each([
    ["/", "home"],
    ["/timeline", "timeline"],
    ["/library", "library"],
    ["/first-times", "first-times"],
    ["/reviews", "reviews"],
    ["/reviews/2025", "reviews"],
    ["/tags", "tags"],
    ["/trash", "trash"],
    ["/settings", "settings"],
    ["/settings/export", "settings"],
    ["/settings/import", "import"],
    ["/items/abc", null],
    ["/no-such-page", null],
    ["/library-old", null],
  ])("maps %s to %s", (pathname, destination) => {
    expect(destinationForPathname(pathname)).toBe(destination);
  });

  it("sends an Entry back to where it belongs", () => {
    const entry = {
      deleted_at: null,
      is_first_time: false,
      item_subtype: "entry",
    };
    expect(destinationForEntry(entry)).toBe("library");
    expect(destinationForEntry({ ...entry, item_subtype: "chapter" })).toBe(
      "timeline",
    );
    expect(destinationForEntry({ ...entry, is_first_time: true })).toBe(
      "first-times",
    );
    expect(
      destinationForEntry({
        deleted_at: "2026-10-01T00:00:00Z",
        is_first_time: true,
        item_subtype: "chapter",
      }),
    ).toBe("trash");
  });
});
