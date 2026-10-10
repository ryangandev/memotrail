"use client";

import { useState, type ReactNode } from "react";
import { Badge } from "@/components/badge";
import { Button } from "@/components/button";
import { CaptureComposer } from "@/components/capture-composer";
import { CaptureProvider } from "@/components/capture-provider";
import { EntryRichTextContent } from "@/components/entry-rich-text-content";
import { FocusedRecordView } from "@/components/focused-record-detail";
import { Icon } from "@/components/icon";
import { ProgressiveImage } from "@/components/progressive-image";
import {
  RecordCard,
  RecordCardBody,
  RecordCardVisual,
} from "@/components/record-card";
import record from "@/components/record-workspace.module.css";
import { RichTextEditor } from "@/components/rich-text-editor";
import { SectionHeader } from "@/components/section-header";
import { SeparatedList } from "@/components/separated-list";
import type { EntryRichText } from "@/lib/data/rich-text";
import styles from "./page.module.css";
import { homePhotos, loadedImage, sampleRichText } from "./samples";
import { Specimen, SpecimenCase } from "./specimen";

// The record, writing, and list specimens, with the same content as the iOS gallery.

export function RichTextSpecimen() {
  const [form, setForm] = useState<EntryRichText | null>(null);
  const [embedded, setEmbedded] = useState<EntryRichText | null>(null);
  return (
    <Specimen
      api="EntryRichTextContent · body · richText; RichTextEditor · text · richText · placeholder · variant: form | embedded · disabled · maxLength"
      description="Saved writing and the editor that writes it. Form is a bordered field; embedded sits inside a surface that is already a field, like the capture composer."
      id="rich-text"
      title="RichText"
    >
      <div className={styles.specimenCases}>
        <SpecimenCase id="rich-text-content">
          <EntryRichTextContent
            body={sampleRichText.text}
            richText={sampleRichText}
          />
        </SpecimenCase>
        <SpecimenCase id="rich-text-form">
          <div className={styles.richTextField}>
            <span>Note</span>
            <RichTextEditor
              label="Note"
              maxLength={1_000}
              onChange={setForm}
              placeholder="Write what you want to remember"
              richText={form}
              text={form?.text ?? ""}
              variant="form"
            />
          </div>
        </SpecimenCase>
        <SpecimenCase id="rich-text-embedded">
          <div className={styles.richTextField}>
            <RichTextEditor
              label="Entry text"
              maxLength={1_000}
              onChange={setEmbedded}
              placeholder="What is on your mind?"
              richText={embedded}
              text={embedded?.text ?? ""}
              variant="embedded"
            />
          </div>
        </SpecimenCase>
      </div>
    </Specimen>
  );
}

export function RecordCardSpecimen() {
  const [message, setMessage] = useState(
    "Interactive state has not been activated.",
  );
  return (
    <Specimen
      api="ariaLabel · onClick · className; composable RecordCardVisual and RecordCardBody"
      description="Each record view lays out its own body inside the shared shell. The visual prefers a photo, then a map of the Location, then the record's mark."
      id="record-card"
      title="RecordCard"
    >
      <div className={styles.specimenCases}>
        <SpecimenCase id="record-card-photo">
          <div className={styles.cardSpecimen}>
            <RecordCard
              ariaLabel="Maple Street flat, Since Jun 1, 2021"
              className={record.homeCard}
              onClick={() => setMessage("Opened the Maple Street flat.")}
            >
              <RecordCardVisual className={record.homeVisual}>
                <ProgressiveImage alt="" src={loadedImage} />
                <Badge
                  className={record.currentBadge}
                  size="micro"
                  tone="glassAccent"
                  uppercase
                >
                  Current
                </Badge>
                <Badge
                  className={record.photoBadge}
                  size="micro"
                  tone="inverse"
                  uppercase
                >
                  3 photos
                </Badge>
              </RecordCardVisual>
              <RecordCardFields
                duration="5 years"
                facts={[
                  { icon: "map", text: "Portland, Oregon, United States" },
                ]}
                range="Since Jun 1, 2021"
                tags={["home", "family"]}
                title="Maple Street flat"
              />
            </RecordCard>
          </div>
        </SpecimenCase>
        <SpecimenCase id="record-card-mark">
          <div className={styles.cardSpecimen}>
            <RecordCard
              ariaLabel="Red touring bike, 2012 - 2016"
              className={record.homeCard}
              onClick={() => setMessage("Opened the red touring bike.")}
            >
              <RecordCardVisual className={record.homeVisual}>
                <div className={record.homeMark}>
                  <Icon name="car" size={24} />
                  <span>2012 Trek 520 · Red</span>
                </div>
                <Badge
                  className={record.pastBadge}
                  size="micro"
                  tone="glassNeutral"
                  uppercase
                >
                  Earlier
                </Badge>
              </RecordCardVisual>
              <RecordCardFields
                duration="About 4 years"
                facts={[{ icon: "car", text: "2012 Trek 520 · Red" }]}
                range="2012 - 2016"
                tags={["cycling"]}
                title="Red touring bike"
              />
            </RecordCard>
          </div>
        </SpecimenCase>
        <p className={styles.stateNote} role="status">
          {message}
        </p>
      </div>
    </Specimen>
  );
}

// The Home and Vehicle card body, as their workspaces draw it.
function RecordCardFields({
  duration,
  facts,
  range,
  tags,
  title,
}: {
  duration: string;
  facts: { icon: "car" | "map"; text: string }[];
  range: string;
  tags: string[];
  title: string;
}) {
  return (
    <RecordCardBody className={record.cardBody}>
      <div className={record.cardDates}>
        <time>{range}</time>
        <span>{duration}</span>
      </div>
      <h3>{title}</h3>
      {facts.map((fact) => (
        <p className={record.location} key={fact.text}>
          <Icon name={fact.icon} size={14} />
          {fact.text}
        </p>
      ))}
      <footer>
        <div>
          {tags.map((name) => (
            <Badge key={name} size="micro" tone="neutral">
              #{name}
            </Badge>
          ))}
        </div>
        <Icon name="chevron" size={15} />
      </footer>
    </RecordCardBody>
  );
}

export function FocusedRecordSpecimen() {
  const [message, setMessage] = useState("Edit has not been activated.");
  return (
    <Specimen
      api="FocusedRecordView · kindLabel · title · photos · facts · story · tags · onEdit · children"
      description="The focused Home, Vehicle, and Someday page: photos, labeled facts that skip empty values, then Story and Organize."
      id="focused-record"
      title="FocusedRecord"
    >
      <SpecimenCase id="focused-record-home">
        <div className={styles.focusedRecordFrame}>
          <FocusedRecordView
            facts={[
              { label: "When", value: "Since Jun 1, 2021" },
              { label: "Location", value: "Portland, Oregon, United States" },
              { label: "Address", value: "120 Maple Street" },
              { label: "Why you moved in", value: "Closer to work" },
              { label: "Why you left", value: null },
            ]}
            headingLevel={2}
            kindLabel="Home"
            onEdit={() => setMessage("Edit Home activated.")}
            photos={homePhotos}
            story="Sunny kitchen, a creaky staircase, and the maple that turned red each October."
            tags={["home", "family"]}
            title="Maple Street flat"
          />
          <p className={styles.stateNote} role="status">
            {message}
          </p>
        </div>
      </SpecimenCase>
    </Specimen>
  );
}

/** The same list in a wide, a medium, and a narrow frame, outlined so its wrapping shows. */
function SeparatedFrames({ children }: { children: ReactNode }) {
  return (
    <div className={styles.separatedListFrames}>
      {["wide", "medium", "narrow"].map((frame) => (
        <div
          className={styles.separatedListFrame}
          data-frame={frame}
          key={frame}
        >
          {children}
        </div>
      ))}
    </div>
  );
}

export function SeparatedListSpecimen() {
  return (
    <Specimen
      api="align: start | end · spacing: default | word · className"
      description="Summary and metadata rows. As the frames narrow, facts wrap whole and a separator shows only between two facts on the same line."
      id="separated-list"
      title="SeparatedList"
    >
      <div className={styles.specimenCases}>
        <SpecimenCase id="separated-list-default">
          <SeparatedFrames>
            <SeparatedList>
              <a href="#separated-list">Manage tracks</a>
              <span>8 tracks</span>
              <span>12 moments</span>
              <span>2017 to 2026</span>
            </SeparatedList>
          </SeparatedFrames>
        </SpecimenCase>
        <SpecimenCase id="separated-list-word">
          <SeparatedFrames>
            <SeparatedList spacing="word">
              <span>First Time</span>
              <span>3 earlier versions</span>
              <span>In Trash</span>
            </SeparatedList>
          </SeparatedFrames>
        </SpecimenCase>
        <SpecimenCase id="separated-list-end-aligned">
          <SeparatedFrames>
            <SeparatedList
              align="end"
              className={styles.separatedListAttribution}
            >
              <span>
                Powered by <a href="#separated-list">Geoapify</a>
              </span>
              <a href="#separated-list">© OpenStreetMap contributors</a>
            </SeparatedList>
          </SeparatedFrames>
        </SpecimenCase>
      </div>
    </Specimen>
  );
}

export function SectionHeaderSpecimen() {
  const viewAll = (
    <a className={styles.headerLink} href="#section-header">
      View all
      <Icon name="chevron" size={14} />
    </a>
  );
  return (
    <Specimen
      api="title · variant: section | list · detail · detailAlign: start | end · description · action · headingLevel: 2 | 3 | 4 · headingId"
      description="The heading of a region of a page. Section is a serif title; list is the small uppercase heading above a list. The caller chooses the heading level."
      id="section-header"
      title="SectionHeader"
    >
      <div className={styles.specimenCases}>
        <SpecimenCase id="section-header-section">
          <div className={styles.headerStack}>
            <div data-header="section">
              <SectionHeader
                detail="12 entries"
                headingLevel={4}
                title="Recent Entries"
              />
            </div>
            <div data-header="section-description">
              <SectionHeader
                action={
                  <Button size="small" variant="secondary">
                    Edit
                  </Button>
                }
                description="Pinned to the top of your Library."
                headingLevel={4}
                title="Favorites"
              />
            </div>
            <div data-header="section-action">
              <SectionHeader
                action={viewAll}
                headingLevel={4}
                title="A memory for today"
              />
            </div>
          </div>
        </SpecimenCase>
        <SpecimenCase id="section-header-list">
          <div className={styles.headerStack}>
            <div data-header="list">
              <SectionHeader
                detail="12 items"
                headingLevel={4}
                title="All items"
                variant="list"
              />
            </div>
            <div data-header="list-end">
              <SectionHeader
                action={
                  <a className={styles.headerLink} href="#section-header">
                    3 need organizing
                  </a>
                }
                detail="12 items"
                detailAlign="end"
                headingLevel={4}
                title="All items"
                variant="list"
              />
            </div>
          </div>
        </SpecimenCase>
        <SpecimenCase id="section-header-long">
          <div className={styles.headerColumn} data-header="long">
            <SectionHeader
              action={viewAll}
              headingLevel={4}
              title="Letters, photos, and notes from the summer at the coast house"
            />
          </div>
        </SpecimenCase>
      </div>
    </Specimen>
  );
}

export function CaptureComposerSpecimen() {
  return (
    <Specimen
      api="CaptureComposer · variant: page | dialog · embedded · active · idPrefix; inside CaptureProvider"
      description="Both composers edit one shared draft, so writing in one shows in the other. The draft stays on this device under a gallery-only owner."
      id="capture-composer"
      title="CaptureComposer"
    >
      <CaptureProvider ownerId="design-system-gallery">
        <div className={styles.specimenCases}>
          <SpecimenCase id="capture-composer-page">
            <div className={styles.captureFrame}>
              <CaptureComposer embedded idPrefix="design-capture-page" />
            </div>
          </SpecimenCase>
          <SpecimenCase id="capture-composer-dialog">
            <div className={styles.captureDialogFrame}>
              <CaptureComposer
                active={false}
                idPrefix="design-capture-dialog"
                variant="dialog"
              />
            </div>
          </SpecimenCase>
        </div>
      </CaptureProvider>
    </Specimen>
  );
}
