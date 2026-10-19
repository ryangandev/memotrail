"use client";

import { useRouter } from "next/navigation";
import { useState, type MouseEvent } from "react";
import { resolveReviewNotice } from "@/app/reviews/actions";
import { Button, ButtonLink } from "@/components/button";
import styles from "@/components/review-notice-card.module.css";
import type { ReviewNotice } from "@/lib/data/review-input";

/**
 * The one quiet notice MemoTrail gives about reviews: a year or a Chapter has ended and a
 * review can be made. Nothing has been made or sent; following the link or choosing Not now
 * retires the notice for that year or Chapter for good.
 */
export function ReviewNoticeCard({ notice }: { notice: ReviewNotice }) {
  const router = useRouter();
  const [gone, setGone] = useState(false);
  const [busy, setBusy] = useState(false);
  if (gone) return null;

  const href =
    notice.kind === "year"
      ? `/reviews/${notice.year}`
      : `/items/${notice.chapterId}`;

  async function resolve() {
    setBusy(true);
    try {
      await resolveReviewNotice(notice.subject);
    } catch {
      /* Following the link still works; the notice may show once more. */
    }
  }

  async function follow(event: MouseEvent<HTMLAnchorElement>) {
    if (
      event.metaKey ||
      event.ctrlKey ||
      event.shiftKey ||
      event.altKey ||
      event.button !== 0
    ) {
      void resolve();
      return;
    }
    event.preventDefault();
    await resolve();
    router.push(href);
  }

  async function dismiss() {
    await resolve();
    setGone(true);
    setBusy(false);
  }

  return (
    <section aria-label="Review notice" className={styles.card}>
      <p>
        {notice.kind === "year"
          ? `${notice.year} is behind you. See what the year held.`
          : `${notice.title} has ended. See what this Chapter held.`}
      </p>
      <div className={styles.actions}>
        <ButtonLink
          href={href}
          onClick={(event) => void follow(event)}
          variant="secondary"
        >
          {notice.kind === "year" ? "Open year review" : "Open Chapter"}
        </ButtonLink>
        <Button disabled={busy} onClick={() => void dismiss()} variant="ghost">
          Not now
        </Button>
      </div>
    </section>
  );
}
