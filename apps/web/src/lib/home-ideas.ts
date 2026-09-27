export const homeIdeas = [
  { slug: "split-focus", number: "03", name: "Split Focus" },
  { slug: "ledger-column", number: "01", name: "Ledger Column" },
  { slug: "context-rail", number: "10", name: "Context Rail" },
  { slug: "command-center", number: "07", name: "Command Center" },
  { slug: "data-ribbon", number: "18", name: "Data Ribbon" },
] as const;

export type HomeIdeaSlug = (typeof homeIdeas)[number]["slug"];
