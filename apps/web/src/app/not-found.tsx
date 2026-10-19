import { ButtonLink } from "@/components/button";
import { RouteFallback } from "@/components/route-fallback";

export default function NotFound() {
  return (
    <RouteFallback
      actions={
        <>
          <ButtonLink href="/">Go to Dashboard</ButtonLink>
          <ButtonLink href="/library" variant="secondary">
            Open Library
          </ButtonLink>
        </>
      }
      description="This page does not exist, or it was moved or removed."
      title="Page not found"
    />
  );
}
