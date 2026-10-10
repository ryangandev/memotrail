"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { Button, ButtonLink, IconButton } from "@/components/button";
import { DatePickerField } from "@/components/date-picker-field";
import { Dialog } from "@/components/dialog";
import { EmptyState } from "@/components/empty-state";
import { Icon, type IconName } from "@/components/icon";
import { PageHeader } from "@/components/page-header";
import {
  buttonSizes,
  buttonVariants,
  iconButtonSizes,
  iconButtonVariants,
  type IconButtonVariant,
} from "@/generated/design-system";
import { TextField } from "@/components/text-field";
import styles from "./page.module.css";
import review from "./pending-component-review.module.css";
import controls from "./controls-gallery.module.css";
import { capitalize, SpecimenCase } from "./specimen";

const iconButtonSamples: Record<
  IconButtonVariant,
  { icon: IconName; label: string }
> = {
  primary: { icon: "plus", label: "Add entry" },
  secondary: { icon: "edit", label: "Edit entry" },
  ghost: { icon: "more", label: "More actions for Travel" },
  danger: { icon: "trash", label: "Move entry to Trash" },
};

export function SharedPrimitivesGallery() {
  const confirmationPortal = useRef<HTMLDivElement>(null);
  const formDialogPortal = useRef<HTMLDivElement>(null);
  const choicePortal = useRef<HTMLDivElement>(null);
  const longPortal = useRef<HTMLDivElement>(null);
  const formPortal = useRef<HTMLFormElement>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [active, setActive] = useState<
    "compact" | "standard" | "choice" | "wide" | null
  >(null);
  const [busy, setBusy] = useState(false);
  const [date, setDate] = useState("2026-09-18");
  const [message, setMessage] = useState("No demo actions yet.");
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
    <div className={review.stack}>
      <Sample
        title="Button"
        api="variant · size · loading · disabled · ButtonLink · IconButton"
      >
        <div className={styles.specimenCases}>
          <SpecimenCase id="button-variants">
            {buttonVariants.map((variant) => (
              <Button
                key={variant}
                variant={variant}
                onClick={() => setMessage(`${variant} button activated.`)}
              >
                {capitalize(variant)}
              </Button>
            ))}
          </SpecimenCase>
          <SpecimenCase id="button-disabled">
            {buttonVariants.map((variant) => (
              <Button disabled key={variant} variant={variant}>
                {capitalize(variant)}
              </Button>
            ))}
          </SpecimenCase>
          <SpecimenCase id="button-loading">
            {buttonVariants.map((variant) => (
              <Button key={variant} loading variant={variant}>
                Saving
              </Button>
            ))}
          </SpecimenCase>
          <SpecimenCase id="button-sizes">
            {buttonSizes.map((size) => (
              <Button
                key={size}
                size={size}
                variant="secondary"
                onClick={() => setMessage(`${size} button activated.`)}
              >
                <Icon name="plus" size={16} />
                {capitalize(size)}
              </Button>
            ))}
          </SpecimenCase>
          <SpecimenCase id="button-link">
            <ButtonLink href="#foundations">View foundations</ButtonLink>
            <ButtonLink href="#shared-primitives" variant="secondary">
              Back to primitives
            </ButtonLink>
          </SpecimenCase>
          <SpecimenCase id="icon-button-variants">
            {iconButtonVariants.map((variant) => (
              <IconButton
                key={variant}
                label={iconButtonSamples[variant].label}
                onClick={() =>
                  setMessage(`${iconButtonSamples[variant].label} activated.`)
                }
                variant={variant}
              >
                <Icon name={iconButtonSamples[variant].icon} size={18} />
              </IconButton>
            ))}
          </SpecimenCase>
          <SpecimenCase id="icon-button-sizes">
            <div className={controls.iconRow}>
              {iconButtonSizes.map((size) => (
                <div key={size}>
                  <IconButton
                    label={`Close entry editor, ${size}`}
                    onClick={() => setMessage(`${size} close activated.`)}
                    size={size}
                  >
                    <Icon name="close" size={size === "small" ? 16 : 18} />
                  </IconButton>
                  <code>{size}</code>
                </div>
              ))}
            </div>
          </SpecimenCase>
          <SpecimenCase id="icon-button-states">
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
          </SpecimenCase>
          <p className={styles.stateNote} role="status">
            {message}
          </p>
        </div>
      </Sample>

      <Sample
        title="Dialog"
        api="size: compact | standard | wide · busy · eyebrow · description · footer · keyboard / focus / dismissal"
      >
        <div className={styles.specimenCases}>
          <SpecimenCase id="dialog-confirmation">
            <div className={controls.portal} ref={confirmationPortal} />
            <Dialog
              title="Remove this memory?"
              description="It moves to Trash, where you can restore it later. This demo does not delete anything."
              size="compact"
              open={active === "compact"}
              onOpenChange={(open) => setActive(open ? "compact" : null)}
              portalContainer={confirmationPortal}
              trigger={
                <Button data-specimen-open variant="danger">
                  Open confirmation
                </Button>
              }
              footer={
                <>
                  <Button variant="secondary" onClick={() => setActive(null)}>
                    Cancel
                  </Button>
                  <Button
                    variant="danger"
                    onClick={() => {
                      setActive(null);
                      setMessage(
                        "Demo removal confirmed. Nothing was deleted.",
                      );
                    }}
                  >
                    Remove memory
                  </Button>
                </>
              }
            />
          </SpecimenCase>
          <SpecimenCase id="dialog-form">
            <div className={controls.portal} ref={formDialogPortal} />
            <Dialog
              title="Edit a memory"
              description="Try the calendar, keyboard focus, Escape, outside click, and the saving state."
              open={active === "standard"}
              onOpenChange={(open) => setActive(open ? "standard" : null)}
              busy={busy}
              portalContainer={formDialogPortal}
              trigger={
                <Button data-specimen-open variant="secondary">
                  Open form dialog
                </Button>
              }
              footer={
                <>
                  <Button
                    variant="secondary"
                    disabled={busy}
                    onClick={() => setActive(null)}
                  >
                    Cancel
                  </Button>
                  <Button
                    form="review-memory-form"
                    type="submit"
                    loading={busy}
                  >
                    {busy ? "Saving memory" : "Save memory"}
                  </Button>
                </>
              }
            >
              <form
                className={review.stack}
                ref={formPortal}
                id="review-memory-form"
                onSubmit={(event) => {
                  event.preventDefault();
                  save();
                }}
              >
                <TextField
                  defaultValue="A moment worth keeping"
                  disabled={busy}
                  label="Title"
                  required
                />
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
          </SpecimenCase>
          <SpecimenCase id="dialog-short-choice">
            <div className={controls.portal} ref={choicePortal} />
            <Dialog
              eyebrow="New entry"
              title="What are you adding?"
              closeLabel="Close entry type chooser"
              size="compact"
              open={active === "choice"}
              onOpenChange={(open) => setActive(open ? "choice" : null)}
              portalContainer={choicePortal}
              trigger={
                <Button data-specimen-open variant="secondary">
                  Open short choice
                </Button>
              }
            >
              <div className={controls.choices}>
                {(
                  [
                    ["timeline", "Moment"],
                    ["home", "Home"],
                  ] as const
                ).map(([icon, title]) => (
                  <Button
                    key={title}
                    onClick={() => {
                      setActive(null);
                      setMessage(`Demo ${title} chosen. Nothing was created.`);
                    }}
                    variant="secondary"
                  >
                    <Icon name={icon} size={16} />
                    {title}
                  </Button>
                ))}
              </div>
            </Dialog>
          </SpecimenCase>
          <SpecimenCase id="dialog-long-content">
            <div className={controls.portal} ref={longPortal} />
            <Dialog
              title="A longer story"
              description="Wide dialog with a scrolling body and a footer that stays visible."
              size="wide"
              open={active === "wide"}
              onOpenChange={(open) => setActive(open ? "wide" : null)}
              portalContainer={longPortal}
              trigger={
                <Button data-specimen-open variant="secondary">
                  Open long content
                </Button>
              }
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
          </SpecimenCase>
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
        <div className={styles.specimenCases}>
          <SpecimenCase id="page-header-full">
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
          </SpecimenCase>
          <SpecimenCase id="page-header-title-only">
            <PageHeader headingLevel={2} title="First sourdough loaf at home" />
          </SpecimenCase>
        </div>
      </Sample>

      <Sample
        title="EmptyState"
        api="title · description · icon · actions · onClick"
      >
        <div className={styles.specimenCases}>
          <SpecimenCase id="empty-state-with-action">
            <EmptyState
              headingLevel={3}
              icon={<Icon name="plus" size={24} />}
              title="Your Life Wiki is empty"
              description="Capture a memory to begin building your trail."
              actions={
                <Button onClick={() => setActive("standard")}>
                  Add your first memory
                </Button>
              }
            />
          </SpecimenCase>
          <SpecimenCase id="empty-state-informational">
            <EmptyState
              headingLevel={3}
              title="No photos yet"
              description="Photos you add to this Home appear here."
            />
          </SpecimenCase>
          <SpecimenCase id="empty-state-button">
            <EmptyState
              icon={<Icon name="star" size={24} />}
              title="Start with a first worth remembering"
              description="Add the first time you did something new."
              onClick={() => setMessage("Empty state action activated.")}
            />
          </SpecimenCase>
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
