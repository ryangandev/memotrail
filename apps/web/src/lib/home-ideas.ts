export const homeIdeas = [
  { slug: "data-ribbon", number: "18", name: "Data Ribbon" },
] as const;

export type HomeIdeaSlug = (typeof homeIdeas)[number]["slug"];
