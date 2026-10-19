"use client";

import { useEffect } from "react";
import { Button, ButtonLink } from "@/components/button";
import { RouteFallback } from "@/components/route-fallback";
import "./globals.css";

/**
 * The last resort, for a failure in the root layout itself. It replaces the
 * whole document, so it brings its own styles and has no workspace shell.
 */
export default function GlobalError({
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
    <html lang="en">
      <body>
        <title>MemoTrail</title>
        <main>
          <RouteFallback
            actions={
              <>
                <Button onClick={() => retry()}>Try again</Button>
                <ButtonLink href="/" variant="secondary">
                  Go to Dashboard
                </ButtonLink>
              </>
            }
            description="Something went wrong while opening MemoTrail. Nothing you saved was changed."
            title="MemoTrail could not load"
          />
        </main>
      </body>
    </html>
  );
}
