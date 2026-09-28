import { redirect } from "next/navigation";
import type { RawSearchParams } from "@/lib/data/search-input";

export default async function SearchRedirect({
  searchParams,
}: {
  searchParams: Promise<RawSearchParams>;
}) {
  const parameters = new URLSearchParams();
  for (const [key, value] of Object.entries(await searchParams)) {
    if (Array.isArray(value)) {
      for (const item of value) parameters.append(key, item);
    } else if (value !== undefined) {
      parameters.set(key, value);
    }
  }
  const query = parameters.toString();
  redirect(query ? `/library?${query}` : "/library");
}
