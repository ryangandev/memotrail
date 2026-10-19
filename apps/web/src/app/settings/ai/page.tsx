import { redirect } from "next/navigation";

// The paused AI capabilities page is gone. Bookmarks land on the review settings.
export default function AISettingsPage() {
  redirect("/settings#reviews");
}
