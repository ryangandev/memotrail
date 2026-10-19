export type ReviewLanguage = "en" | "zh";

/**
 * The language a review is written in follows the language the person writes in: Chinese
 * when more of the text that will be sent is Han characters than Latin words, otherwise English.
 * The interface around a review stays English either way.
 */
export function chooseReviewLanguage(texts: readonly string[]): ReviewLanguage {
  let han = 0;
  let latinWords = 0;
  for (const text of texts) {
    han += text.match(/\p{Script=Han}/gu)?.length ?? 0;
    latinWords += text.match(/\p{Script=Latin}+/gu)?.length ?? 0;
  }
  return han > latinWords ? "zh" : "en";
}
