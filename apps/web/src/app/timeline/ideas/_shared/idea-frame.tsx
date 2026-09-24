import Link from "next/link";
import type { ReactNode } from "react";
import { ButtonLink } from "@/components/button";
import { PageFrame } from "@/components/page-frame";
import { PageHeader } from "@/components/page-header";
import type { TimelineWorkspace } from "@/lib/data/timeline";
import type { TimelineIdeaModel } from "./model";
import { timelineIdeaCreateHref } from "./model";
import { timelineIdeaLinks } from "./navigation";
import styles from "./idea-frame.module.css";

export function TimelineIdeaFrame({
  children,
  description,
  eyebrow,
  model,
  path,
  title,
  workspace,
}: {
  children: ReactNode;
  description: string;
  eyebrow: string;
  model: TimelineIdeaModel;
  path: string;
  title: string;
  workspace: TimelineWorkspace;
}) {
  return (
    <PageFrame className={styles.frame} variant="canvas">
      <PageHeader
        actions={
          <ButtonLink href={timelineIdeaCreateHref(path)} variant="primary">
            Add moment
          </ButtonLink>
        }
        description={description}
        eyebrow={`Timeline idea ${eyebrow}`}
        title={title}
      />
      <div className={styles.meta}>
        <span>{model.items.length} recorded moments and periods</span>
        <span aria-hidden="true">·</span>
        <span>{model.tracks.length} visible tracks</span>
        <span aria-hidden="true">·</span>
        <Link href="/timeline/tracks">Manage tracks</Link>
      </div>
      <nav aria-label="Timeline design ideas" className={styles.mobileIdeas}>
        {timelineIdeaLinks.map((idea) => (
          <Link
            aria-current={path === idea.href ? "page" : undefined}
            href={idea.href}
            key={idea.href}
          >
            {idea.label}
          </Link>
        ))}
      </nav>
      {workspace.birthDateAvailable && !workspace.birthDate ? (
        <p className={styles.notice}>
          Your birth date has not been set. Set it in the main Timeline to
          anchor the beginning of your story.
        </p>
      ) : null}
      {workspace.loadError ? (
        <p className={styles.notice} role="alert">
          {workspace.loadError}
        </p>
      ) : model.tracks.length === 0 ? (
        <p className={styles.notice}>
          Your Timeline needs a visible track. Open Manage tracks to add or show
          one.
        </p>
      ) : model.items.length === 0 ? (
        <p className={styles.notice}>
          Your Timeline is ready. Add a moment or period to see this design with
          your own story.
        </p>
      ) : (
        children
      )}
    </PageFrame>
  );
}
