import { redirect } from "next/navigation";

export default async function OrganizationPage({
  searchParams,
}: {
  searchParams: Promise<{ kind?: string }>;
}) {
  const params = await searchParams;
  redirect(params.kind === "tag" ? "/tags" : "/collections");
}
