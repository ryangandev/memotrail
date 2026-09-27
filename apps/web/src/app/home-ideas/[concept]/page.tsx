import { notFound } from "next/navigation";
import { getHomeWorkspace } from "@/lib/data/home";
import { homeIdeas } from "@/lib/home-ideas";
import { HomeIdea } from "../_components/home-idea";

export const dynamic = "force-dynamic";

export default async function HomeIdeaPage({
  params,
}: {
  params: Promise<{ concept: string }>;
}) {
  if (process.env.NODE_ENV === "production") notFound();
  const { concept } = await params;
  const idea = homeIdeas.find((item) => item.slug === concept);
  if (!idea) notFound();
  const workspace = await getHomeWorkspace();
  if (!workspace) return null;
  return <HomeIdea concept={idea.slug} workspace={workspace} />;
}
