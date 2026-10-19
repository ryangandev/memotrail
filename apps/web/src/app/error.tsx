"use client";

import { useEffect } from "react";
import { Button, ButtonLink } from "@/components/button";
import { RouteFallback } from "@/components/route-fallback";

/**
 * Replaces a page that failed to render, inside the workspace shell, so
 * navigation stays available and trying again needs no reload.
 */
export default function RouteError({
  error,
  retry,
}: {
  error: Error & { digest?: string };
  retry: () => void;
}) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <RouteFallback
      actions={
        <>
          <Button onClick={() => retry()}>Try again</Button>
          <ButtonLink href="/" variant="secondary">
            Go to Dashboard
          </ButtonLink>
        </>
      }
      description="Something went wrong while showing this page. Nothing you saved was changed."
      title="This page could not load"
    />
  );
}
