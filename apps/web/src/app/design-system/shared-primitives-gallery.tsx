"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { Button, ButtonLink, IconButton } from "@/components/button";
import { DatePickerField } from "@/components/date-picker-field";
import { Dialog } from "@/components/dialog";
import { EmptyState } from "@/components/empty-state";
import { Icon } from "@/components/icon";
import { PageHeader } from "@/components/page-header";
import styles from "./page.module.css";
import review from "./pending-component-review.module.css";

export function SharedPrimitivesGallery() {
  const portal = useRef<HTMLDivElement>(null);
  const formPortal = useRef<HTMLFormElement>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [active, setActive] = useState<"compact" | "standard" | "wide" | null>(
    null,
  );
  const [busy, setBusy] = useState(false);
  const [date, setDate] = useState("2026-09-18");
  const [message, setMessage] = useState("No demo actions yet.");
  const [filtered, setFiltered] = useState(true);
  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current);
    },
    [],
  );

  function save() {
    setBusy(true);
    timer.current = setTimeout(() => {
      setBusy(false);
      setActive(null);
      setMessage(`Demo saved for ${date}. No data was uploaded.`);
    }, 1500);
  }

  return (
    <div className={review.stack} ref={portal}>
      <Sample
        title="Button"
        api="primary · secondary · ghost · danger · small / medium / large"
      >
        <div className={review.stack}>
          {(["primary", "secondary", "ghost", "danger"] as const).map(
            (variant) => (
              <div className={review.row} key={variant}>
                <span className={review.rowLabel}>{variant}</span>
                <Button
                  variant={variant}
                  onClick={() => setMessage(`${variant} button activated.`)}
                >
                  Continue
                </Button>
                <Button variant={variant} disabled>
                  Disabled
                </Button>
                <Button variant={variant} loading>
                  Saving
                </Button>
              </div>
            ),
          )}
          <div className={review.row}>
            <span className={review.rowLabel}>Sizes</span>
            {(["small", "medium", "large"] as const).map((size) => (
              <Button
                key={size}
                size={size}
                variant="secondary"
                onClick={() => setMessage(`${size} button activated.`)}
              >
                <Icon name="plus" size={16} />
                {size}
              </Button>
            ))}
          </div>
          <div className={review.row}>
            <span className={review.rowLabel}>Icon / link</span>
            <IconButton
              label="Add demo entry"
              onClick={() => setMessage("Add icon activated.")}
            >
              <Icon name="plus" size={18} />
            </IconButton>
            <IconButton label="Disabled add entry" disabled>
              <Icon name="plus" size={18} />
            </IconButton>
            <IconButton label="Saving entry" loading>
              <Icon name="plus" size={18} />
            </IconButton>
            <ButtonLink href="#foundations">View foundations</ButtonLink>
          </div>
          <p className={styles.stateNote} role="status">
            {message}
          </p>
        </div>
      </Sample>

      <Sample
        title="Dialog"
        api="compact · standard · wide · busy · keyboard / focus / dismissal"
      >
        <div className={review.row}>
          <Dialog
            title="Remove this memory?"
            description="A compact confirmation example. This demo does not delete anything."
            size="compact"
            open={active === "compact"}
            onOpenChange={(open) => setActive(open ? "compact" : null)}
            portalContainer={portal}
            trigger={<Button variant="danger">Open confirmation</Button>}
            footer={
              <>
                <Button variant="secondary" onClick={() => setActive(null)}>
                  Cancel
                </Button>
                <Button
                  variant="danger"
                  onClick={() => {
                    setActive(null);
                    setMessage("Demo removal confirmed. Nothing was deleted.");
                  }}
                >
                  Remove memory
                </Button>
              </>
            }
          >
            The memory will be moved to Recently deleted, where it can be
            restored.
          </Dialog>
          <Dialog
            title="Edit a memory"
            description="Try the calendar, keyboard focus, Escape, outside click, and the saving state."
            open={active === "standard"}
            onOpenChange={(open) => setActive(open ? "standard" : null)}
            busy={busy}
            portalContainer={portal}
            trigger={<Button variant="secondary">Open form dialog</Button>}
            footer={
              <>
                <Button
                  variant="secondary"
                  disabled={busy}
                  onClick={() => setActive(null)}
                >
                  Cancel
                </Button>
                <Button form="review-memory-form" type="submit" loading={busy}>
                  {busy ? "Saving memory" : "Save memory"}
                </Button>
              </>
            }
          >
            <form
              ref={formPortal}
              id="review-memory-form"
              onSubmit={(event) => {
                event.preventDefault();
                save();
              }}
            >
              <DatePickerField
                portalContainer={formPortal}
                label="Memory date"
                value={date}
                onChange={setDate}
                disabled={busy}
                required
              />
            </form>
          </Dialog>
          <Dialog
            title="A longer story"
            description="Wide dialog with a scrolling body and a footer that stays visible."
            size="wide"
            open={active === "wide"}
            onOpenChange={(open) => setActive(open ? "wide" : null)}
            portalContainer={portal}
            trigger={<Button variant="secondary">Open long content</Button>}
            footer={
              <Button onClick={() => setActive(null)}>Done reading</Button>
            }
          >
            <div className={review.stack}>
              {Array.from({ length: 12 }, (_, index) => (
                <p className={review.paragraph} key={index}>
                  <strong>Chapter {index + 1}.</strong> Small details give a
                  memory its shape: the place, the people, and the things we
                  noticed along the way. This sample exercises long content
                  without changing the page behind it.
                </p>
              ))}
            </div>
          </Dialog>
        </div>
        <p className={styles.stateNote}>
          Saving is simulated for 1.5 seconds. While saving, dismissal and
          duplicate submission are disabled.
        </p>
      </Sample>

      <Sample
        title="PageHeader"
        api="eyebrow · title · description · optional actions · responsive"
      >
        <div className={review.stack}>
          <PageHeader
            headingLevel={2}
            eyebrow="Your life, remembered"
            title="Memories"
            description="The moments, people, and places that make up your story."
            actions={
              <>
                <Button
                  variant="secondary"
                  onClick={() => setMessage("Header filter activated.")}
                >
                  Filter
                </Button>
                <Button onClick={() => setActive("standard")}>
                  <Icon name="plus" size={16} />
                  Add memory
                </Button>
              </>
            }
          />
          <div className={review.separator} />
          <PageHeader
            headingLevel={2}
            title="A lifetime of small moments and meaningful places"
            description="A longer heading without actions, to review wrapping at narrow widths."
          />
        </div>
      </Sample>

      <Sample
        title="EmptyState"
        api="initial · filtered · no action · optional icon"
      >
        <div className={review.stack}>
          <EmptyState
            headingLevel={3}
            icon={<Icon name="plus" size={24} />}
            title="Your story starts here"
            description="Capture a memory to begin building your trail."
            actions={
              <Button onClick={() => setActive("standard")}>
                Add your first memory
              </Button>
            }
          />
          <EmptyState
            headingLevel={3}
            icon={<Icon name="search" size={24} />}
            title={filtered ? "No matching memories" : "Filters cleared"}
            description={
              filtered
                ? "Try another search or clear your filters."
                : "This gallery uses local demo state, so no records are fetched."
            }
            actions={
              <Button
                variant="secondary"
                onClick={() => setFiltered(!filtered)}
              >
                {filtered ? "Clear filters" : "Reset demo filters"}
              </Button>
            }
          />
          <EmptyState
            headingLevel={3}
            title="Nothing here yet"
            description="A quiet, informational state without an action or decorative icon."
          />
        </div>
      </Sample>
    </div>
  );
}

function Sample({
  title,
  api,
  children,
}: {
  title: string;
  api: string;
  children: ReactNode;
}) {
  return (
    <article className={styles.specimen}>
      <header>
        <h3>{title}</h3>
        <code>{api}</code>
      </header>
      <div className={styles.specimenBody}>{children}</div>
    </article>
  );
}
