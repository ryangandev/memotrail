"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { ButtonLink } from "@/components/button";
import { Icon } from "@/components/icon";
import { PageFrame } from "@/components/page-frame";
import { PageHeader } from "@/components/page-header";
import { ProgressiveImage } from "@/components/progressive-image";
import { HomeEditor } from "@/components/homes-workspace";
import { VehicleEditor } from "@/components/vehicles-workspace";
import { FirstTimeEditor } from "@/components/first-times-workspace";
import { GoalEditor } from "@/components/goals-workspace";
import { PersonEditor } from "@/components/people-workspace";
import {
  homeLocationLabel,
  homeRangeLabel,
  type HomeRecord,
} from "@/lib/data/home-record";
import {
  vehicleFactsLabel,
  vehicleRangeLabel,
  type VehicleRecord,
} from "@/lib/data/vehicle-record";
import {
  goalHorizonLabels,
  goalStatusLabels,
  goalTargetLabel,
  type GoalLinkOption,
  type GoalRecord,
} from "@/lib/data/goal-record";
import { occurrenceLabel } from "@/lib/data/occurrence";
import type { FirstTimeEntry } from "@/lib/data/first-times";
import {
  personEntryTitle,
  type Person,
  type PersonEntry,
} from "@/lib/data/person";
import { wikiEntryHref } from "@/lib/data/wiki-item";
import styles from "./focused-record-detail.module.css";

type Shared = {
  collectionOptions: string[];
  ownerId: string;
  tagOptions: string[];
};
type Props =
  | ({ kind: "home"; record: HomeRecord } & Shared)
  | ({ kind: "vehicle"; record: VehicleRecord } & Shared)
  | ({ kind: "first-time"; record: FirstTimeEntry } & Shared)
  | ({
      kind: "goal";
      record: GoalRecord;
      linkOptions: GoalLinkOption[];
    } & Shared)
  | ({ kind: "person"; record: Person; entries: PersonEntry[] } & Shared);

const paths = {
  home: "/homes",
  vehicle: "/vehicles",
  "first-time": "/first-times",
  goal: "/goals",
  person: "/people",
};
const labels = {
  home: "Home",
  vehicle: "Vehicle",
  "first-time": "First Time",
  goal: "Goal",
  person: "Person",
};

export function FocusedRecordDetail(props: Props) {
  const router = useRouter();
  const [editing, setEditing] = useState(false);
  const [saved, setSaved] = useState<Props["record"] | null>(null);
  const record =
    saved &&
    saved.id === props.record.id &&
    saved.revision >= props.record.revision
      ? saved
      : props.record;
  const back = paths[props.kind];
  const label = labels[props.kind];

  function closeEdit() {
    setEditing(false);
  }

  const sharedEditorProps = {
    collectionOptions: props.collectionOptions,
    onClose: closeEdit,
    ownerId: props.ownerId,
    presentation: "page" as const,
    tagOptions: props.tagOptions,
  };

  return (
    <PageFrame variant="compact" className={styles.frame}>
      {editing ? (
        props.kind === "home" ? (
          <HomeEditor
            {...sharedEditorProps}
            home={record as HomeRecord}
            onSaved={setSaved}
            onTrashed={() => router.push(back)}
          />
        ) : props.kind === "vehicle" ? (
          <VehicleEditor
            {...sharedEditorProps}
            vehicle={record as VehicleRecord}
            onSaved={setSaved}
            onTrashed={() => router.push(back)}
          />
        ) : props.kind === "first-time" ? (
          <FirstTimeEditor
            {...sharedEditorProps}
            entry={record as FirstTimeEntry}
            onSaved={setSaved}
            onTrashed={() => router.push(back)}
          />
        ) : props.kind === "goal" ? (
          <GoalEditor
            {...sharedEditorProps}
            goal={record as GoalRecord}
            linkOptions={props.linkOptions}
            onTrashed={() => router.push(back)}
          />
        ) : (
          <PersonEditor
            entries={props.entries}
            person={record as Person}
            onClose={closeEdit}
            presentation="page"
            onTrashed={() => router.push(back)}
          />
        )
      ) : (
        <>
          <PageHeader
            eyebrow={label}
            title={
              props.kind === "person"
                ? (record as Person).name
                : (record as HomeRecord).title
            }
            actions={
              <button
                aria-label={`Edit ${label}`}
                className={styles.editAction}
                type="button"
                onClick={() => setEditing(true)}
              >
                <Icon name="edit" size={18} />
                <span>Edit</span>
              </button>
            }
          />
          <RecordContent kind={props.kind} record={record} />
          {props.kind !== "person" ? (
            <ButtonLink
              href={`/history?entry=${record.id}`}
              variant="secondary"
            >
              Version history
            </ButtonLink>
          ) : null}
        </>
      )}
    </PageFrame>
  );
}

function Fact({
  label,
  value,
}: {
  label: string;
  value: string | number | null | undefined;
}) {
  if (value === null || value === undefined || value === "") return null;
  return (
    <div className={styles.fact}>
      <dt>{label}</dt>
      <dd>{value}</dd>
    </div>
  );
}

function RecordContent({
  kind,
  record,
}: {
  kind: Props["kind"];
  record: Props["record"];
}) {
  const common =
    kind === "person"
      ? null
      : (record as HomeRecord | VehicleRecord | FirstTimeEntry | GoalRecord);
  const photos =
    common?.attachments.filter((photo) =>
      "variant" in photo ? photo.variant === "original" : true,
    ) ?? [];
  const body = kind === "person" ? (record as Person).notes : common?.body;
  const collections = common?.collectionNames ?? [];
  const tags = common?.tagNames ?? [];
  return (
    <article className={styles.content}>
      {photos.length > 0 ? (
        <div className={styles.photos}>
          {photos.map((photo, index) =>
            photo.imageUrl ? (
              <ProgressiveImage
                key={photo.id}
                src={photo.imageUrl}
                alt={
                  photo.originalFilename ?? `${labels[kind]} photo ${index + 1}`
                }
              />
            ) : null,
          )}
        </div>
      ) : null}
      <dl className={styles.facts}>
        {kind === "home" ? (
          <>
            <Fact label="When" value={homeRangeLabel(record as HomeRecord)} />
            <Fact
              label="Location"
              value={homeLocationLabel(record as HomeRecord)}
            />
            <Fact label="Address" value={(record as HomeRecord).address} />
            <Fact
              label="Why you moved in"
              value={(record as HomeRecord).moveInReason}
            />
            <Fact
              label="Why you left"
              value={(record as HomeRecord).moveOutReason}
            />
            <Fact
              label="Place notes"
              value={(record as HomeRecord).placeNotes}
            />
          </>
        ) : null}
        {kind === "vehicle" ? (
          <>
            <Fact
              label="When"
              value={vehicleRangeLabel(record as VehicleRecord)}
            />
            <Fact
              label="Vehicle"
              value={vehicleFactsLabel(record as VehicleRecord)}
            />
            <Fact
              label="Location"
              value={(record as VehicleRecord).location?.name}
            />
          </>
        ) : null}
        {kind === "first-time" ? (
          <>
            <Fact
              label="When"
              value={occurrenceLabel({
                occurredAt: (record as FirstTimeEntry).occurredStart,
                occurredEnd: (record as FirstTimeEntry).occurredEnd,
                occurredLabel: (record as FirstTimeEntry).occurredLabel,
                occurredTimezone:
                  (record as FirstTimeEntry).occurredTimezone ?? "UTC",
                datePrecision: (record as FirstTimeEntry).datePrecision,
              })}
            />
            <Fact
              label="Location"
              value={(record as FirstTimeEntry).location?.name}
            />
          </>
        ) : null}
        {kind === "goal" ? (
          <>
            <Fact
              label="Status"
              value={goalStatusLabels[(record as GoalRecord).status]}
            />
            <Fact
              label="Horizon"
              value={goalHorizonLabels[(record as GoalRecord).horizon]}
            />
            <Fact
              label="Target"
              value={goalTargetLabel(record as GoalRecord)}
            />
          </>
        ) : null}
        {kind === "person" ? (
          <Fact
            label="Relationship"
            value={(record as Person).relationship_label}
          />
        ) : null}
      </dl>
      {body ? (
        <section className={styles.section}>
          <h2>{kind === "person" ? "Notes" : "Story"}</h2>
          <p className={styles.prose}>{body}</p>
        </section>
      ) : null}
      {collections.length || tags.length ? (
        <section className={styles.section}>
          <h2>Organize</h2>
          <div className={styles.chips}>
            {collections.map((name) => (
              <span key={`collection:${name}`}>{name}</span>
            ))}
            {tags.map((name) => (
              <span key={`tag:${name}`}>#{name}</span>
            ))}
          </div>
        </section>
      ) : null}
      {kind === "person" && (record as Person).linked_entries.length ? (
        <section className={styles.section}>
          <h2>Connected Items</h2>
          <ul>
            {(record as Person).linked_entries.map((entry) => (
              <li key={entry.id}>
                <a
                  href={wikiEntryHref({
                    id: entry.id,
                    inboxStatus: "organized",
                    itemKind: entry.item_kind,
                    itemSubtype: entry.item_subtype,
                  })}
                >
                  {personEntryTitle(entry)}
                </a>
              </li>
            ))}
          </ul>
        </section>
      ) : null}
      {kind === "goal" && (record as GoalRecord).relatedEntries.length ? (
        <section className={styles.section}>
          <h2>Connected Items</h2>
          <ul>
            {(record as GoalRecord).relatedEntries.map((entry) => (
              <li key={entry.id}>
                <a
                  href={wikiEntryHref({
                    id: entry.id,
                    inboxStatus: "organized",
                    itemKind: entry.itemKind,
                    itemSubtype: entry.itemSubtype,
                  })}
                >
                  {entry.title}
                </a>
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </article>
  );
}
