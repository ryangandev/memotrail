import type { Metadata } from "next";
import { notFound } from "next/navigation";
import tokens from "../../../../../packages/design-tokens/tokens.json";
import { PageFrame } from "@/components/page-frame";
import { DesignSystemGallery } from "./design-system-gallery";
import styles from "./page.module.css";

export const metadata: Metadata = {
  title: "Web Design System | MemoTrail",
  description: "Development gallery for MemoTrail's current Web UI system.",
};

export default function DesignSystemPage() {
  if (process.env.NODE_ENV === "production") notFound();

  return (
    <PageFrame className={styles.page} variant="canvas">
      <header className={styles.hero}>
        <p className={styles.eyebrow}>Development only</p>
        <h1>Web Design System</h1>
        <p>
          A live inventory of MemoTrail&apos;s current tokens, reusable Web
          components, variants, and states. Specimens import shared component
          implementations used by production pages.
        </p>
      </header>
      <DesignSystemGallery tokens={tokens} />
    </PageFrame>
  );
}
