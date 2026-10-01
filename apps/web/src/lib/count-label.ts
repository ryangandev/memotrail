/**
 * A count with its noun, such as "1 Entry", "3 Entries", or "2 people".
 * Nouns ending in a consonant and "y" take "ies"; pass `plural` for any other irregular form.
 */
export function countLabel(
  count: number,
  singular: string,
  plural = /[^aeiou]y$/i.test(singular)
    ? `${singular.slice(0, -1)}ies`
    : `${singular}s`,
) {
  return `${count} ${count === 1 ? singular : plural}`;
}
