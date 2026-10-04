"use client";

import { useState } from "react";
import { BrandMark } from "@/components/brand-mark";
import { Badge } from "@/components/badge";
import { Button } from "@/components/button";
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
import { SearchField } from "@/components/search-field";
import { SelectField } from "@/components/select-field";
import { SeparatedList } from "@/components/separated-list";
import { TextField } from "@/components/text-field";
import { notify } from "@/components/app-toast";
import type { OccurrenceDraft } from "@/lib/data/occurrence";
import type { EntryRichText } from "@/lib/data/rich-text";
import styles from "./page.module.css";
import { SharedPrimitivesGallery } from "./shared-primitives-gallery";
import { BrandMotionPreview } from "./brand-motion-preview";

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
  const [searchSample, setSearchSample] = useState("");
  const [searchMessage, setSearchMessage] = useState(
    "Type a query to try this local-only preview.",
  );
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
    label: "",
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
        description="Approved shared primitives used by production pages. These interactive examples use local demo state only."
        id="shared-primitives"
        index="00"
        title="Shared primitives"
      >
        <SharedPrimitivesGallery />
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
        description="Shared identity and the complete production icon set. Icon accepts name and size; BrandMark accepts className, optional counter-rotation motion, and collapsed state."
        id="identity"
        index="02"
        title="Identity and icons"
      >
        <div className={styles.identityRow} data-brand-identity>
          <BrandMark className={styles.brandMark} />
          <div>
            <strong>BrandMark</strong>
            <p>Inline SVG used by authentication and workspace navigation.</p>
          </div>
        </div>
        <Specimen
          description="The selected sidebar animation, using the shared BrandMark. Toggle the panel to preview both directions."
          id="brand-motion"
          title="Brand motion"
        >
          <BrandMotionPreview />
        </Specimen>
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
        description="TextField, SearchField, SelectField, and the current production date, rich-text, occurrence, and organization editors are reusable. TextField is a proposed replacement for route-level plain text inputs; other textareas, labels, and validation messages are still route-level patterns."
        id="forms"
        index="04"
        title="Forms"
      >
        <Specimen
          api="label · size: small | medium | large · disabled · native text input props"
          description="Proposed plain text input for review. Its font, height, border, and focus surface match SearchField and SelectField. The Settings page still uses its existing field."
          id="text-field"
          title="TextField"
        >
          <div className={styles.formGrid}>
            <TextField defaultValue="Alex Morgan" label="Preferred name" />
            <TextField label="Empty text field" placeholder="Add a name" />
            <TextField
              disabled
              label="Disabled text field"
              placeholder="Unavailable"
              size="small"
            />
          </div>
        </Specimen>
        <Specimen
          api="label · hideLabel · size: small | medium | large · disabled · native input props"
          description="One focus surface for the icon and text. The search action stays composable, so each feature can choose its own submit behavior."
          id="search-field"
          title="SearchField"
        >
          <form
            className={styles.searchFieldDemo}
            onSubmit={(event) => {
              event.preventDefault();
              setSearchMessage(
                searchSample.trim()
                  ? `Demo search: ${searchSample.trim()}. No request was sent.`
                  : "Enter a search term first.",
              );
            }}
          >
            <SearchField
              label="Search Locations"
              onChange={(event) => setSearchSample(event.target.value)}
              placeholder="Search for an address"
              value={searchSample}
            />
            <Button type="submit" variant="secondary">
              Search
            </Button>
          </form>
          <div className={styles.searchFieldVariants}>
            <SearchField
              label="Compact search"
              placeholder="Search your trail"
              size="small"
            />
            <SearchField
              disabled
              label="Disabled search"
              placeholder="Search unavailable"
            />
          </div>
          <p className={styles.stateNote} role="status">
            {searchMessage}
          </p>
        </Specimen>
        <Specimen
          api="label · size: small | medium | large · disabled · native select props"
          description="A labeled native select with the same surface and focus treatment as SearchField."
          title="SelectField"
        >
          <div className={styles.formGrid}>
            <SelectField defaultValue="all" label="Show records">
              <option value="all">All records</option>
              <option value="entries">Entries</option>
              <option value="entities">Homes & vehicles</option>
            </SelectField>
            <SelectField disabled label="Unavailable filter" size="small">
              <option>Unavailable</option>
            </SelectField>
          </div>
        </Specimen>
        <Specimen
          api="size: small | medium | large · granularity: day | month | year · editable · includeTime · disabled"
          description="Date values, time controls, and calendar text use the shared form typography."
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
          title="Badge"
          api="micro | small | medium · semantic and photo tones · uppercase · one line · tags use # text"
        >
          <div className={styles.badgeExamples}>
            <Badge size="micro" uppercase>
              Entry
            </Badge>
            <Badge size="small" tone="neutral" uppercase>
              Home
            </Badge>
            <Badge size="medium">Keyword search</Badge>
            <Badge size="small" tone="warm">
              Needs organizing
            </Badge>
            <Badge size="small" tone="outline">
              Vehicle
            </Badge>
            <Badge size="small" tone="inverse">
              3 photos
            </Badge>
            <Badge title="A long label that stays on one line">
              A long label that stays on one line
            </Badge>
            <Badge size="medium" title="#learning">
              #learning
            </Badge>
            <Badge size="medium" title="#旅行">
              #旅行
            </Badge>
            <Badge
              size="medium"
              title="#A long tag name that stays within the available width"
            >
              #A long tag name that stays within the available width
            </Badge>
          </div>
        </Specimen>

        <Specimen
          api="names · input · options · disabled"
          title="EntryOrganizationEditor"
        >
          <div className={styles.formGrid}>
            <EntryOrganizationEditor
              disabled={false}
              input={tagInput}
              names={tags}
              onChange={setTags}
              onInputChange={setTagInput}
              options={["family", "travel", "milestone", "home"]}
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
        description="RecordCard is the shared interactive record surface used by Homes, Vehicles, and First Times."
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

        <Specimen
          api="align: start | end · spacing: default | word · className"
          description="Summary and metadata rows. As the frames narrow, facts wrap whole and a separator shows only between two facts on the same line."
          id="separated-list"
          title="SeparatedList"
        >
          <div className={styles.separatedListFrames}>
            {["wide", "medium", "narrow"].map((frame) => (
              <div
                className={styles.separatedListFrame}
                data-frame={frame}
                key={frame}
              >
                <SeparatedList>
                  <a href="#separated-list">Manage tracks</a>
                  <span>8 tracks</span>
                  <span>12 moments</span>
                  <span>2017 to 2026</span>
                </SeparatedList>
                <SeparatedList spacing="word">
                  <span>First Time</span>
                  <span>3 earlier versions</span>
                  <span>In Trash</span>
                </SeparatedList>
                <SeparatedList
                  align="end"
                  className={styles.separatedListAttribution}
                >
                  <span>
                    Powered by <a href="#separated-list">Geoapify</a>
                  </span>
                  <a href="#separated-list">© OpenStreetMap contributors</a>
                </SeparatedList>
              </div>
            ))}
          </div>
        </Specimen>
      </GallerySection>

      <GallerySection
        description="Transient action feedback and reviewed media states. The shared EmptyState is demonstrated above."
        id="feedback"
        index="06"
        title="Feedback and media states"
      >
        <div className={styles.feedbackGrid}>
          <Specimen
            api="notify.success · notify.error · notify.info"
            title="Toast"
          >
            <div className={styles.toastPreviewActions}>
              <Button onClick={() => notify.success("Changes saved.")}>
                Show success
              </Button>
              <Button
                variant="secondary"
                onClick={() => notify.info("Moved to Trash.")}
              >
                Show info
              </Button>
              <Button
                variant="danger"
                onClick={() => notify.error("Could not save. Try again.")}
              >
                Show error
              </Button>
            </div>
          </Specimen>
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
  id,
  title,
}: {
  api?: string;
  children: React.ReactNode;
  description?: string;
  id?: string;
  title: string;
}) {
  return (
    <article className={styles.specimen} id={id}>
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
