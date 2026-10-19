import { redirect } from "next/navigation";
import type { RawSearchParams } from "@/lib/data/search-input";

// Keep old bookmarks safe without retaining the retired exploration UI. A search or filter in
// the old address carries over to Library.
export default async function ExplorePage({
  searchParams,
}: {
  searchParams: Promise<RawSearchParams>;
}) {
  const parameters = new URLSearchParams();
  for (const [key, value] of Object.entries(await searchParams)) {
    for (const item of Array.isArray(value) ? value : value ? [value] : []) {
      parameters.append(key, item);
    }
  }
  const query = parameters.toString();
  redirect(query ? `/library?${query}` : "/library");
}
