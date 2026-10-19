import { describe, expect, it } from "vitest";
import {
  matchPassage,
  matchedByFromReasons,
  quickResultDescription,
} from "./match-presentation";

describe("matchedByFromReasons", () => {
  it("tells words from meaning", () => {
    expect(matchedByFromReasons(["Title", "Body"])).toBe("words");
    expect(matchedByFromReasons(["Meaning"])).toBe("meaning");
    expect(matchedByFromReasons(["Body", "Meaning"])).toBe("both");
    expect(matchedByFromReasons([])).toBe("words");
  });
});

describe("matchPassage", () => {
  const body =
    "First sentence here. ".repeat(10) + "The climbing gym guy fixed my bike.";

  it("is null for an Entry with a single chunk", () => {
    expect(matchPassage(body, 0, 20, 1)).toBeNull();
    expect(matchPassage(body, 0, 20, null)).toBeNull();
    expect(matchPassage(body, null, null, 3)).toBeNull();
  });

  it("cuts the matched range from the body with ellipses where text continues", () => {
    const start = body.indexOf("The climbing");
    expect(matchPassage(body, start, body.length, 2)).toBe(
      "...The climbing gym guy fixed my bike.",
    );
    expect(matchPassage(body, 0, 20, 2)).toBe("First sentence here....");
  });

  it("counts positions in code points", () => {
    const text = "😀😀 你好，世界。再见。";
    expect(matchPassage(text, 3, 8, 2)).toBe("...你好，世界...");
  });

  it("clips a long passage to 200 characters", () => {
    const long = "word ".repeat(100);
    const passage = matchPassage(long, 0, long.length, 2);
    expect(passage).not.toBeNull();
    expect(Array.from(passage ?? "").length).toBeLessThanOrEqual(203);
    expect(passage?.endsWith("...")).toBe(true);
  });

  it("collapses line breaks", () => {
    expect(matchPassage("one\n\ntwo\nthree", 0, 14, 2)).toBe("one two three");
  });

  it("ignores ranges that do not fit the body", () => {
    expect(matchPassage("short", 0, 99, 2)).toBeNull();
    expect(matchPassage("short", 3, 2, 2)).toBeNull();
    expect(matchPassage("short", -1, 2, 2)).toBeNull();
  });
});

describe("quickResultDescription", () => {
  it("labels meaning-only results", () => {
    expect(
      quickResultDescription({
        label: "Entry",
        matchedBy: "meaning",
        subtitle: "A note",
      }),
    ).toBe("Entry · Meaning · A note");
    expect(
      quickResultDescription({
        label: "Entry",
        matchedBy: "both",
        subtitle: "A note",
      }),
    ).toBe("Entry · A note");
    expect(
      quickResultDescription({
        label: "Entry",
        matchedBy: "words",
        subtitle: "A note",
      }),
    ).toBe("Entry · A note");
  });
});
