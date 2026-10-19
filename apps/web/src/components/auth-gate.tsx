"use client";

import { useState } from "react";
import { BrandMark } from "@/components/brand-mark";
import { createClient } from "@/lib/supabase/client";
import styles from "./auth-gate.module.css";

type AuthGateProps = {
  configured: boolean;
};

export function AuthGate({ configured }: AuthGateProps) {
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isRedirecting, setIsRedirecting] = useState(false);

  async function signInWithGoogle() {
    setErrorMessage(null);
    setIsRedirecting(true);

    try {
      const callbackUrl = new URL("/auth/callback", window.location.origin);
      callbackUrl.searchParams.set("next", "/");

      const supabase = createClient();
      const { error } = await supabase.auth.signInWithOAuth({
        provider: "google",
        options: { redirectTo: callbackUrl.toString() },
      });

      if (error) {
        setErrorMessage(error.message);
        setIsRedirecting(false);
      }
    } catch {
      setErrorMessage(
        "MemoTrail could not start Google Sign-In. Check the public Supabase configuration and try again.",
      );
      setIsRedirecting(false);
    }
  }

  return (
    <div className={styles.shell}>
      <header className={styles.header}>
        <MemoTrailBrand />
      </header>

      <main className={styles.main}>
        <section aria-labelledby="welcome-heading" className={styles.intro}>
          <h1 id="welcome-heading">
            The one private place your life is written down.
          </h1>
          <p>
            Jot down a thought in seconds, find it again from any
            half-remembered clue, and get each Chapter of your life back.
          </p>

          {configured ? (
            <button
              className={styles.googleButton}
              disabled={isRedirecting}
              onClick={signInWithGoogle}
              type="button"
            >
              <GoogleMark />
              <span>
                {isRedirecting ? "Opening Google…" : "Continue with Google"}
              </span>
            </button>
          ) : (
            <div className={styles.setupState} role="status">
              <strong>Setup needed</strong>
              <span>
                Add the public Supabase URL and publishable key, then restart
                the Web app.
              </span>
            </div>
          )}

          {errorMessage ? (
            <p className={styles.error} role="alert">
              {errorMessage}
            </p>
          ) : null}

          <small className={styles.privacyNote}>
            Google verifies your identity. MemoTrail never receives your Google
            password.
          </small>
        </section>

        <ul aria-hidden="true" className={styles.sample}>
          <li>
            <time>Today</time>
            <div>
              <strong>Why do people need to keep learning?</strong>
              <span>Learning</span>
            </div>
          </li>
          <li>
            <time>Jul 3, 2026</time>
            <div>
              <strong>First time skiing</strong>
              <span>First Time</span>
            </div>
          </li>
          <li>
            <time>2001 - 2012</time>
            <div>
              <strong>Growing up in China</strong>
              <span>Chapter</span>
            </div>
          </li>
        </ul>
      </main>
    </div>
  );
}

function MemoTrailBrand() {
  return (
    <div className={styles.brand} aria-label="MemoTrail">
      <BrandMark className={styles.brandMark} />
      <strong>MemoTrail</strong>
    </div>
  );
}

function GoogleMark() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <path
        fill="#4285F4"
        d="M21.6 12.23c0-.71-.06-1.4-.18-2.06H12v3.9h5.38a4.6 4.6 0 0 1-2 3.01v2.53h3.24c1.9-1.75 2.98-4.33 2.98-7.38Z"
      />
      <path
        fill="#34A853"
        d="M12 22c2.7 0 4.98-.9 6.63-2.4l-3.24-2.52c-.9.6-2.05.96-3.39.96-2.61 0-4.82-1.76-5.61-4.13H3.04v2.6A10 10 0 0 0 12 22Z"
      />
      <path
        fill="#FBBC05"
        d="M6.39 13.91A6 6 0 0 1 6.08 12c0-.66.11-1.3.31-1.91v-2.6H3.04A10 10 0 0 0 2 12c0 1.61.39 3.14 1.04 4.51l3.35-2.6Z"
      />
      <path
        fill="#EA4335"
        d="M12 5.96c1.47 0 2.79.5 3.83 1.5l2.87-2.88A9.63 9.63 0 0 0 12 2a10 10 0 0 0-8.96 5.49l3.35 2.6C7.18 7.72 9.39 5.96 12 5.96Z"
      />
    </svg>
  );
}
