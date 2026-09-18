"use client";

import { useState } from "react";
import { BrandMark } from "@/components/brand-mark";
import { DatePickerField } from "@/components/date-picker-field";
import { EntryOrganizationEditor } from "@/components/entry-organization-editor";
import { EntryPhotoField } from "@/components/entry-photo-field";
import { EntryRichTextContent } from "@/components/entry-rich-text-content";
import { Icon, iconNames } from "@/components/icon";
import { OccurrenceEditor } from "@/components/occurrence-editor";
import { PhotoUploadProgress } from "@/components/photo-upload-progress";
import { ProgressiveImage } from "@/components/progressive-image";
import {
  RecordCard,
  RecordCardBody,
  RecordCardVisual,
} from "@/components/record-card";
import { RichTextEditor } from "@/components/rich-text-editor";
import type { OccurrenceDraft } from "@/lib/data/occurrence";
import type { EntryRichText } from "@/lib/data/rich-text";
import styles from "./page.module.css";
import { PendingComponentReview } from "./pending-component-review";

type TokenSet = {
  meta: { name: string; version: string };
  color: {
    light: Record<string, string>;
    dark: Record<string, string>;
  };
  font: {
    family: Record<string, string>;
    size: Record<string, number>;
    lineHeight: Record<string, number>;
    weight: Record<string, number>;
  };
  space: Record<string, number>;
  radius: Record<string, number>;
  motion: Record<string, number>;
  shadow: Record<string, string>;
};

const sampleRichText: EntryRichText = {
  document: {
    content: [
      {
        content: [
          {
            marks: [{ type: "bold" }],
            text: "Formatted memory",
            type: "text",
          },
          { text: " with durable, validated structure.", type: "text" },
        ],
        type: "paragraph",
      },
      {
        content: [
          {
            content: [
              {
                content: [{ text: "One remembered detail", type: "text" }],
                type: "paragraph",
              },
            ],
            type: "listItem",
          },
        ],
        type: "bulletList",
      },
    ],
    type: "doc",
  },
  text: "Formatted memory with durable, validated structure.\nOne remembered detail",
  version: 1,
};

const loadedImage =
  "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='640' height='360' viewBox='0 0 640 360'%3E%3Crect width='640' height='360' fill='%23DDE8E1'/%3E%3Cpath d='M0 285 190 115l112 95 90-72 248 147v75H0Z' fill='%2382AD98'/%3E%3Ccircle cx='492' cy='92' r='38' fill='%23A76346'/%3E%3C/svg%3E";

const typographyRoles = [
  { family: "serif", name: "display", size: "display", weight: "medium" },
  { family: "serif", name: "title", size: "title", weight: "medium" },
  {
    family: "sans",
    name: "titleSmall",
    size: "title-small",
    weight: "semibold",
  },
  {
    family: "sans",
    name: "bodyLarge",
    size: "body-large",
    weight: "regular",
  },
  { family: "sans", name: "body", size: "body", weight: "regular" },
  { family: "sans", name: "label", size: "label", weight: "medium" },
  { family: "sans", name: "caption", size: "caption", weight: "medium" },
] as const;

export function DesignSystemGallery({ tokens }: { tokens: TokenSet }) {
  const [galleryTheme, setGalleryTheme] = useState<"system" | "light" | "dark">(
    "system",
  );
  const [date, setDate] = useState("2026-09-17");
  const [emptyDate, setEmptyDate] = useState("");
  const [dateTime, setDateTime] = useState("2026-09-17T14:30");
  const [month, setMonth] = useState("2026-09");
  const [year, setYear] = useState("2026");
  const [editorValue, setEditorValue] = useState<EntryRichText | null>(null);
  const [editorText, setEditorText] = useState("");
  const [tags, setTags] = useState(["family", "travel"]);
  const [tagInput, setTagInput] = useState("");
  const [collections, setCollections] = useState(["Early years"]);
  const [collectionInput, setCollectionInput] = useState("");
  const [existingPhotos, setExistingPhotos] = useState([
    {
      id: "design-system-photo",
      imageUrl: loadedImage,
      originalFilename: "coast-memory.jpg",
    },
  ]);
  const [pendingPhotos, setPendingPhotos] = useState<File[]>([]);
  const [occurrence, setOccurrence] = useState<OccurrenceDraft>({
    precision: "day",
    start: "2026-09-17",
    end: "",
    endMode: "date",
    label: "A clear September afternoon",
    timezone: "America/Los_Angeles",
  });
  const [recordMessage, setRecordMessage] = useState(
    "Interactive state has not been activated.",
  );

  return (
    <div
      className={styles.gallery}
      data-theme={galleryTheme === "system" ? undefined : galleryTheme}
    >
      <div className={styles.galleryToolbar}>
        <label>
          <span>Gallery theme</span>
          <select
            onChange={(event) =>
              setGalleryTheme(event.target.value as "system" | "light" | "dark")
            }
            value={galleryTheme}
          >
            <option value="system">System</option>
            <option value="light">Light</option>
            <option value="dark">Dark</option>
          </select>
        </label>
        <p>This control changes only the development gallery preview.</p>
      </div>
      <GallerySection
        description="New shared primitives awaiting review. These examples use local demo state only; production pages have not adopted them."
        id="pending-review"
        index="00"
        title="Pending review"
      >
        <PendingComponentReview />
      </GallerySection>
      <GallerySection
        description="Values come directly from packages/design-tokens/tokens.json. The nested previews exercise the generated light and dark CSS variables."
        id="foundations"
        index="01"
        title="Foundations"
      >
        <Specimen
          description={`${Object.keys(tokens.color.light).length} semantic colors with matched light and dark names.`}
          title="Colors"
        >
          <div className={styles.themeGrid}>
            {(["light", "dark"] as const).map((theme) => (
              <div
                className={styles.themePreview}
                data-theme={theme}
                key={theme}
              >
                <h3>{capitalize(theme)}</h3>
                <div className={styles.colorGrid}>
                  {Object.entries(tokens.color[theme]).map(([name, value]) => (
                    <div className={styles.colorToken} key={name}>
                      <span
                        aria-hidden="true"
                        style={{ background: `var(--mt-color-${kebab(name)})` }}
                      />
                      <strong>{name}</strong>
                      <code>{value}</code>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </Specimen>

        <Specimen
          description="The source provides primitive family, size, line-height, and weight tokens. These samples show the semantic combinations currently hardcoded by the Swift generator and repeatedly assembled in Web CSS."
          title="Typography"
        >
          <div className={styles.typeList}>
            {typographyRoles.map((role) => (
              <div className={styles.typeRow} key={role.name}>
                <p
                  style={{
                    fontFamily: `var(--mt-font-family-${role.family})`,
                    fontSize: `var(--mt-font-size-${role.size})`,
                    fontWeight: `var(--mt-font-weight-${role.weight})`,
                  }}
                >
                  A life in progress
                </p>
                <code>
                  {role.name} · {role.family} · {role.size} · {role.weight}
                </code>
              </div>
            ))}
          </div>
        </Specimen>

        <div className={styles.foundationGrid}>
          <Specimen title="Spacing">
            <div className={styles.scaleList}>
              {Object.entries(tokens.space).map(([name, value]) => (
                <div className={styles.scaleRow} key={name}>
                  <code>space.{name}</code>
                  <span
                    aria-hidden="true"
                    style={{ width: `var(--mt-space-${name})` }}
                  />
                  <small>{value}px</small>
                </div>
              ))}
            </div>
          </Specimen>

          <Specimen title="Radius">
            <div className={styles.radiusGrid}>
              {Object.entries(tokens.radius).map(([name, value]) => (
                <div key={name}>
                  <span
                    aria-hidden="true"
                    style={{ borderRadius: `var(--mt-radius-${name})` }}
                  />
                  <code>{name}</code>
                  <small>{value}px</small>
                </div>
              ))}
            </div>
          </Specimen>

          <Specimen title="Shadow">
            <div className={styles.shadowGrid}>
              {Object.entries(tokens.shadow).map(([name, value]) => (
                <div key={name}>
                  <span style={{ boxShadow: `var(--mt-shadow-${name})` }} />
                  <code>{name}</code>
                  <small>{value}</small>
                </div>
              ))}
            </div>
          </Specimen>

          <Specimen title="Motion">
            <div className={styles.motionList}>
              {Object.entries(tokens.motion).map(([name, value]) => (
                <div key={name}>
                  <code>{name}</code>
                  <span style={{ animationDuration: `${value}ms` }} />
                  <small>{value}ms</small>
                </div>
              ))}
            </div>
          </Specimen>
        </div>
      </GallerySection>

      <GallerySection
        description="Shared identity and the complete production icon set. Icon accepts name and size; BrandMark accepts className."
        id="identity"
        index="02"
        title="Identity and icons"
      >
        <div className={styles.identityRow}>
          <BrandMark className={styles.brandMark} />
          <div>
            <strong>BrandMark</strong>
            <p>Inline SVG used by authentication and workspace navigation.</p>
          </div>
        </div>
        <div className={styles.iconGrid}>
          {iconNames.map((name) => (
            <div key={name}>
              <Icon name={name} size={20} />
              <code>{name}</code>
            </div>
          ))}
        </div>
      </GallerySection>

      <GallerySection
        description="PageFrame is the canonical outer geometry. This gallery itself uses the canvas variant."
        id="layout"
        index="03"
        title="Layout"
      >
        <div className={styles.variantTable}>
          <div>
            <strong>compact</strong>
            <span>880px · forms and focused reading</span>
          </div>
          <div>
            <strong>standard</strong>
            <span>960px · lists and search</span>
          </div>
          <div>
            <strong>wide</strong>
            <span>1080px · dashboards and card grids</span>
          </div>
          <div>
            <strong>canvas</strong>
            <span>1180px · dense spatial views</span>
          </div>
        </div>
      </GallerySection>

      <GallerySection
        description="The current production date, rich-text, occurrence, and organization editors are reusable. Plain text inputs, selects, textareas, labels, and validation messages are still route-level patterns."
        id="forms"
        index="04"
        title="Forms"
      >
        <Specimen
          api="size: small | medium | large · granularity: day | month | year · editable · includeTime · disabled"
          title="DatePickerField"
        >
          <div className={styles.formGrid}>
            <DatePickerField
              label="Filled date"
              onChange={setDate}
              size="small"
              value={date}
            />
            <DatePickerField
              label="Empty date"
              onChange={setEmptyDate}
              size="medium"
              value={emptyDate}
            />
            <DatePickerField
              editable={false}
              label="Picker only"
              onChange={setEmptyDate}
              size="large"
              value={emptyDate}
            />
            <DatePickerField
              includeTime
              label="Exact date and time"
              onChange={setDateTime}
              value={dateTime}
            />
            <DatePickerField
              granularity="month"
              label="Month precision"
              onChange={setMonth}
              value={month}
            />
            <DatePickerField
              granularity="year"
              label="Year precision"
              onChange={setYear}
              value={year}
            />
            <DatePickerField
              disabled
              label="Disabled"
              onChange={() => undefined}
              value="2026-09-17"
            />
          </div>
        </Specimen>

        <Specimen
          api="variant: dialog | form | page · disabled · autoFocus · maxLength"
          title="RichTextEditor"
        >
          <div className={styles.editorGrid}>
            <RichTextEditor
              label="Editable memory"
              maxLength={1_000}
              onChange={(value) => {
                setEditorValue(value);
                setEditorText(value?.text ?? "");
              }}
              placeholder="Write a memory..."
              richText={editorValue}
              text={editorText}
              variant="form"
            />
            <RichTextEditor
              disabled
              label="Disabled memory"
              maxLength={1_000}
              onChange={() => undefined}
              placeholder="Write a memory..."
              richText={null}
              text="This editor is disabled."
              variant="form"
            />
          </div>
        </Specimen>

        <Specimen
          api="kind: collection | tag · names · options · disabled"
          title="EntryOrganizationEditor"
        >
          <div className={styles.formGrid}>
            <EntryOrganizationEditor
              disabled={false}
              input={tagInput}
              kind="tag"
              names={tags}
              onChange={setTags}
              onInputChange={setTagInput}
              options={["family", "travel", "milestone", "home"]}
            />
            <EntryOrganizationEditor
              disabled={false}
              input={collectionInput}
              kind="collection"
              names={collections}
              onChange={setCollections}
              onInputChange={setCollectionInput}
              options={["Early years", "Family archive", "Travel journals"]}
            />
          </div>
        </Specimen>

        <Specimen
          api="point · span · disabled · defaultTimezone · eight precision modes"
          title="OccurrenceEditor"
        >
          <div className={styles.occurrenceSpecimen}>
            <OccurrenceEditor
              defaultTimezone="America/Los_Angeles"
              disabled={false}
              onChange={setOccurrence}
              value={occurrence}
            />
          </div>
        </Specimen>

        <Specimen
          api="existingPhotos · pendingPhotos · limit · progress · disabled"
          title="EntryPhotoField"
        >
          <div className={styles.formGrid}>
            <EntryPhotoField
              disabled={false}
              existingPhotos={existingPhotos}
              limit={10}
              onRemoveExisting={(photo) =>
                setExistingPhotos((current) =>
                  current.filter((item) => item.id !== photo.id),
                )
              }
              onRemovePending={(index) =>
                setPendingPhotos((current) =>
                  current.filter((_, itemIndex) => itemIndex !== index),
                )
              }
              onSelect={(files) =>
                setPendingPhotos((current) => [...current, ...files])
              }
              pendingPhotos={pendingPhotos}
              progress={
                pendingPhotos.length
                  ? { completed: 0, total: pendingPhotos.length }
                  : null
              }
              recordLabel="Entry"
            />
            <EntryPhotoField
              disabled
              existingPhotos={[]}
              limit={10}
              onRemoveExisting={() => undefined}
              onRemovePending={() => undefined}
              onSelect={() => undefined}
              pendingPhotos={[]}
              progress={null}
              recordLabel="Entry"
            />
          </div>
          <p className={styles.stateNote}>
            Select local files to preview the circular batch progress centered
            on the first pending photo. It counts completed files, not uploaded
            bytes.
          </p>
        </Specimen>
      </GallerySection>

      <GallerySection
        description="RecordCard is the shared interactive record surface used by Homes, Vehicles, Places, and First Times. Other card families remain route-specific."
        id="containers"
        index="05"
        title="Containers and data display"
      >
        <Specimen
          api="ariaLabel · onClick · className; composable RecordCardVisual and RecordCardBody"
          title="RecordCard"
        >
          <div className={styles.cardSpecimen}>
            <RecordCard
              ariaLabel="Open sample memory"
              onClick={() => setRecordMessage("RecordCard onClick fired.")}
            >
              <RecordCardVisual>
                <ProgressiveImage alt="" src={loadedImage} />
              </RecordCardVisual>
              <RecordCardBody>
                <p className={styles.cardEyebrow}>Memory</p>
                <h3>First trip to the coast</h3>
                <p>A production RecordCard composed with its real subparts.</p>
              </RecordCardBody>
            </RecordCard>
            <small role="status">{recordMessage}</small>
          </div>
        </Specimen>

        <Specimen
          api="body · richText or metadata · className"
          title="EntryRichTextContent"
        >
          <EntryRichTextContent
            body={sampleRichText.text}
            richText={sampleRichText}
          />
        </Specimen>
      </GallerySection>

      <GallerySection
        description="Reviewed media feedback. The proposed generic EmptyState is in Pending review above."
        id="feedback"
        index="06"
        title="Feedback and media states"
      >
        <div className={styles.feedbackGrid}>
          <Specimen api="completed · total" title="PhotoUploadProgress">
            <PhotoUploadProgress progress={{ completed: 3, total: 5 }} />
          </Specimen>
          <Specimen
            api="loading · loaded · failed · fit: cover | contain · fallback"
            title="ProgressiveImage"
          >
            <div className={styles.imageStates}>
              <div>
                <ProgressiveImage alt="Loading sample" />
                <small>Loading skeleton</small>
              </div>
              <div>
                <ProgressiveImage alt="Loaded sample" src={loadedImage} />
                <small>Loaded</small>
              </div>
              <div>
                <ProgressiveImage
                  alt="Failed sample"
                  fallback="Photo unavailable"
                  src="/design-system/intentionally-missing-image.png"
                />
                <small>Failure fallback</small>
              </div>
            </div>
            <p className={styles.stateNote}>
              Loading is normally transient while the image decodes. Failure
              replaces the image and skeleton with the supplied fallback.
            </p>
          </Specimen>
        </div>
      </GallerySection>
    </div>
  );
}

function GallerySection({
  children,
  description,
  id,
  index,
  title,
}: {
  children: React.ReactNode;
  description: string;
  id: string;
  index: string;
  title: string;
}) {
  return (
    <section aria-labelledby={`${id}-title`} className={styles.section} id={id}>
      <header className={styles.sectionHeader}>
        <p>{index}</p>
        <div>
          <h2 id={`${id}-title`}>{title}</h2>
          <p>{description}</p>
        </div>
      </header>
      <div className={styles.sectionBody}>{children}</div>
    </section>
  );
}

function Specimen({
  api,
  children,
  description,
  title,
}: {
  api?: string;
  children: React.ReactNode;
  description?: string;
  title: string;
}) {
  return (
    <article className={styles.specimen}>
      <header>
        <div>
          <h3>{title}</h3>
          {description ? <p>{description}</p> : null}
        </div>
        {api ? <code>{api}</code> : null}
      </header>
      <div className={styles.specimenBody}>{children}</div>
    </article>
  );
}

function kebab(value: string) {
  return value.replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase();
}

function capitalize(value: string) {
  return `${value[0].toUpperCase()}${value.slice(1)}`;
}
