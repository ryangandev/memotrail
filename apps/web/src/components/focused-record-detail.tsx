"use client";

import { useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { Badge } from "@/components/badge";
import { Button } from "@/components/button";
import { Icon } from "@/components/icon";
import { PageFrame } from "@/components/page-frame";
import { PageHeader } from "@/components/page-header";
import { PhotoPreviewDialog } from "@/components/photo-preview-dialog";
import { ProgressiveImage } from "@/components/progressive-image";
import { SectionHeader } from "@/components/section-header";
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
  goal: "Someday item",
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
        <FocusedRecordView
          facts={recordFacts(props.kind, record)}
          kindLabel={label}
          onEdit={() => setEditing(true)}
          photos={recordPhotos(props.kind, record)}
          story={record.body}
          storyTitle={props.kind === "goal" ? "Notes" : "Story"}
          tags={record.tagNames}
          title={record.title}
        >
          {props.kind === "goal" ? (
            <RelatedEntries goal={record as GoalRecord} />
          ) : null}
        </FocusedRecordView>
      )}
    </PageFrame>
  );
}

export type FocusedRecordPhoto = { id: string; name: string; src: string };
export type FocusedRecordFact = {
  label: string;
  value: string | number | null | undefined;
};

/**
 * A record's own page: its Kind and title with Edit, its photos, facts, Story, and tags, then
 * any sections that belong to one Kind. Specified in
 * packages/design-system/components/focused-record.yaml.
 */
export function FocusedRecordView({
  children,
  facts,
  headingLevel,
  kindLabel,
  onEdit,
  photos,
  story,
  storyTitle = "Story",
  tags,
  title,
}: {
  children?: ReactNode;
  facts: FocusedRecordFact[];
  /** The page's own title is the h1; a preview inside another page passes 2. */
  headingLevel?: 1 | 2;
  kindLabel: string;
  onEdit: () => void;
  photos: FocusedRecordPhoto[];
  story?: string | null;
  storyTitle?: string;
  tags: string[];
  title: string;
}) {
  const visibleFacts = facts.filter(
    ({ value }) => value !== null && value !== undefined && value !== "",
  );
  return (
    <div className={styles.view} data-ui-focused-record>
      <PageHeader
        eyebrow={kindLabel}
        headingLevel={headingLevel}
        title={title}
        actions={
          <Button
            aria-label={`Edit ${kindLabel}`}
            onClick={onEdit}
            size="small"
            variant="ghost"
          >
            <Icon name="edit" size={14} />
            Edit
          </Button>
        }
      />
      <article className={styles.content}>
        {photos.length > 0 ? <RecordPhotos photos={photos} /> : null}
        {visibleFacts.length > 0 ? (
          <dl className={styles.facts}>
            {visibleFacts.map((fact) => (
              <div className={styles.fact} key={fact.label}>
                <dt>{fact.label}</dt>
                <dd>{fact.value}</dd>
              </div>
            ))}
          </dl>
        ) : null}
        {story ? (
          <section className={styles.section}>
            <SectionHeader
              className={styles.sectionHeader}
              title={storyTitle}
            />
            <p className={styles.prose}>{story}</p>
          </section>
        ) : null}
        {tags.length ? (
          <section className={styles.section}>
            <SectionHeader className={styles.sectionHeader} title="Organize" />
            <div className={styles.chips}>
              {tags.map((name) => (
                <Badge key={`tag:${name}`} tone="neutral">
                  #{name}
                </Badge>
              ))}
            </div>
          </section>
        ) : null}
        {children}
      </article>
    </div>
  );
}

// Each photo opens the viewer, which pages through the others, like an Item page's photos.
function RecordPhotos({ photos }: { photos: FocusedRecordPhoto[] }) {
  const [selected, setSelected] = useState<number | null>(null);
  const photo = selected === null ? null : photos[selected];
  return (
    <div className={styles.photos}>
      {photos.map((item, index) => (
        <button
          aria-label={`Preview ${item.name}`}
          className={styles.photo}
          key={item.id}
          onClick={() => setSelected(index)}
          type="button"
        >
          <ProgressiveImage alt={item.name} loading="lazy" src={item.src} />
        </button>
      ))}
      {photo ? (
        <PhotoPreviewDialog
          name={photo.name}
          onClose={() => setSelected(null)}
          onNext={() => setSelected((index) => (index ?? 0) + 1)}
          onPrevious={() => setSelected((index) => (index ?? 0) - 1)}
          position={{ index: selected!, total: photos.length }}
          src={photo.src}
        />
      ) : null}
    </div>
  );
}

function optionalLocationLabel(location: LocationSelection | null | undefined) {
  return location ? locationDisplayLabel(location) : null;
}

function recordPhotos(
  kind: Props["kind"],
  record: Props["record"],
): FocusedRecordPhoto[] {
  const originals = record.attachments.filter((photo) =>
    "variant" in photo ? photo.variant === "original" : true,
  );
  return originals.flatMap((photo, index) =>
    photo.imageUrl
      ? [
          {
            id: photo.id,
            name:
              photo.originalFilename ?? `${labels[kind]} photo ${index + 1}`,
            src: photo.imageUrl,
          },
        ]
      : [],
  );
}

function recordFacts(
  kind: Props["kind"],
  record: Props["record"],
): FocusedRecordFact[] {
  if (kind === "home") {
    const home = record as HomeRecord;
    return [
      { label: "When", value: homeRangeLabel(home) },
      { label: "Location", value: homeLocationLabel(home) },
      { label: "Address", value: home.location?.address },
      { label: "Why you moved in", value: home.moveInReason },
      { label: "Why you left", value: home.moveOutReason },
    ];
  }
  if (kind === "vehicle") {
    const vehicle = record as VehicleRecord;
    return [
      { label: "When", value: vehicleRangeLabel(vehicle) },
      { label: "Vehicle", value: vehicleFactsLabel(vehicle) },
      { label: "Location", value: optionalLocationLabel(vehicle.location) },
    ];
  }
  const goal = record as GoalRecord;
  return [
    { label: "Status", value: goalStatusLabels[goal.status] },
    { label: "Target date", value: goalTargetDate(goal) },
  ];
}

function RelatedEntries({ goal }: { goal: GoalRecord }) {
  if (!goal.relatedEntries.length) return null;
  return (
    <section className={styles.section}>
      <SectionHeader className={styles.sectionHeader} title="First Time" />
      <ul>
        {goal.relatedEntries.map((entry) => (
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
  );
}
