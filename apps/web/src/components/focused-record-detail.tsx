"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Badge } from "@/components/badge";
import { Icon } from "@/components/icon";
import { PageFrame } from "@/components/page-frame";
import { PageHeader } from "@/components/page-header";
import { ProgressiveImage } from "@/components/progressive-image";
import { HomeEditor } from "@/components/homes-workspace";
import { VehicleEditor } from "@/components/vehicles-workspace";
import { GoalEditor } from "@/components/goals-workspace";
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
  goalStatusLabels,
  goalTargetDate,
  type GoalRecord,
} from "@/lib/data/goal-record";
import { wikiEntryHref } from "@/lib/data/wiki-item";
import {
  locationDisplayLabel,
  type LocationSelection,
} from "@/lib/locations/location";
import styles from "./focused-record-detail.module.css";

type Shared = {
  ownerId: string;
  tagOptions: string[];
};
type Props =
  | ({ kind: "home"; record: HomeRecord } & Shared)
  | ({ kind: "vehicle"; record: VehicleRecord } & Shared)
  | ({ kind: "goal"; record: GoalRecord } & Shared);

const paths = {
  home: "/homes",
  vehicle: "/vehicles",
  goal: "/goals",
};
const labels = {
  home: "Home",
  vehicle: "Vehicle",
  goal: "Want to Do",
};

export function FocusedRecordDetail(props: Props) {
  const router = useRouter();
  const [editing, setEditing] = useState(false);
  const [saved, setSaved] = useState<Props["record"] | null>(null);
  // The saved copy bridges the wait for the refreshed page. Once the server
  // reaches its revision, the server copy wins, since it also has the photos
  // uploaded after the save, which leave the revision unchanged.
  const record =
    saved &&
    saved.id === props.record.id &&
    saved.revision > props.record.revision
      ? saved
      : props.record;
  const back = paths[props.kind];
  const label = labels[props.kind];

  function closeEdit() {
    setEditing(false);
  }

  const sharedEditorProps = {
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
        ) : (
          <GoalEditor
            {...sharedEditorProps}
            goal={record as GoalRecord}
            onTrashed={() => router.push(back)}
          />
        )
      ) : (
        <>
          <PageHeader
            eyebrow={label}
            title={record.title}
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
        </>
      )}
    </PageFrame>
  );
}

function optionalLocationLabel(location: LocationSelection | null | undefined) {
  return location ? locationDisplayLabel(location) : null;
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
  const photos = record.attachments.filter((photo) =>
    "variant" in photo ? photo.variant === "original" : true,
  );
  const body = record.body;
  const tags = record.tagNames;
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
            <Fact
              label="Address"
              value={(record as HomeRecord).location?.address}
            />
            <Fact
              label="Why you moved in"
              value={(record as HomeRecord).moveInReason}
            />
            <Fact
              label="Why you left"
              value={(record as HomeRecord).moveOutReason}
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
              value={optionalLocationLabel((record as VehicleRecord).location)}
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
              label="Target date"
              value={goalTargetDate(record as GoalRecord)}
            />
          </>
        ) : null}
      </dl>
      {body ? (
        <section className={styles.section}>
          <h2>{kind === "goal" ? "Notes" : "Story"}</h2>
          <p className={styles.prose}>{body}</p>
        </section>
      ) : null}
      {tags.length ? (
        <section className={styles.section}>
          <h2>Organize</h2>
          <div className={styles.chips}>
            {tags.map((name) => (
              <Badge key={`tag:${name}`} tone="neutral">
                #{name}
              </Badge>
            ))}
          </div>
        </section>
      ) : null}
      {kind === "goal" && (record as GoalRecord).relatedEntries.length ? (
        <section className={styles.section}>
          <h2>First Time</h2>
          <ul>
            {(record as GoalRecord).relatedEntries.map((entry) => (
              <li key={entry.id}>
                <a
                  href={wikiEntryHref({
                    id: entry.id,
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
