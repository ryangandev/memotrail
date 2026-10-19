import { describe, expect, it } from "vitest";
import { chooseReviewLanguage } from "./language";

describe("chooseReviewLanguage", () => {
  it("writes English for English", () => {
    expect(chooseReviewLanguage(["I went for a long walk today."])).toBe("en");
  });
  it("writes Chinese for Chinese", () => {
    expect(chooseReviewLanguage(["今天去了公园，天气很好。"])).toBe("zh");
  });
  it("lets whichever script has more in a mixed journal win", () => {
    expect(
      chooseReviewLanguage(["面试很顺利，我很开心。", "Interview went fine."]),
    ).toBe("zh");
    expect(
      chooseReviewLanguage([
        "The interview went well and I felt relieved afterwards.",
        "今天很好。",
      ]),
    ).toBe("en");
  });
  it("defaults to English with nothing to read", () => {
    expect(chooseReviewLanguage([])).toBe("en");
    expect(chooseReviewLanguage(["123 456"])).toBe("en");
  });
  it("counts across every text", () => {
    expect(chooseReviewLanguage(["今天", "很好", "I am here"])).toBe("zh");
  });
});
