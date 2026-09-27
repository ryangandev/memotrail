import { notFound, redirect } from "next/navigation";

export default function HomeIdeasPage() {
  if (process.env.NODE_ENV === "production") notFound();
  redirect("/home-ideas/data-ribbon");
}
