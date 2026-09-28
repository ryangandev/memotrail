import { redirect } from "next/navigation";

// Keep old bookmarks safe without retaining the retired exploration UI.
export default function ExplorePage() {
  redirect("/library");
}
