"use client";

import { Fragment, useState } from "react";
import { BrandMark } from "@/components/brand-mark";
import { Badge } from "@/components/badge";
import { Button } from "@/components/button";
import { EntryOrganizationEditor } from "@/components/entry-organization-editor";
import { EntryPhotoField } from "@/components/entry-photo-field";
import { EntryRichTextContent } from "@/components/entry-rich-text-content";
import { Icon } from "@/components/icon";
import { OccurrenceEditor } from "@/components/occurrence-editor";
import { PhotoUploadProgress } from "@/components/photo-upload-progress";
import { ProgressiveImage } from "@/components/progressive-image";
import {
  RecordCard,
  RecordCardBody,
  RecordCardVisual,
} from "@/components/record-card";
import { RichTextEditor } from "@/components/rich-text-editor";
import { SectionHeader } from "@/components/section-header";
import { SeparatedList } from "@/components/separated-list";
import { Skeleton } from "@/components/skeleton";
import { badgeSizes, badgeTones } from "@/generated/design-system";
import type { OccurrenceDraft } from "@/lib/data/occurrence";
import type { EntryRichText } from "@/lib/data/rich-text";
import styles from "./page.module.css";
import { SharedPrimitivesGallery } from "./shared-primitives-gallery";
import { ToastSpecimen, WorkspaceSpecimens } from "./controls-gallery";
import { FormControlSpecimens } from "./form-controls-gallery";
import { BrandMotionPreview } from "./brand-motion-preview";
import {
  FoundationTokens,
  IconTokens,
  LayoutTokens,
  type TokenSet,
} from "./foundations-gallery";
import { Specimen, SpecimenCase } from "./specimen";

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

export function DesignSystemGallery({ tokens }: { tokens: TokenSet }) {
  const [galleryTheme, setGalleryTheme] = useState<"system" | "light" | "dark">(
    "system",
  );
  const [editorValue, setEditorValue] = useState<EntryRichText | null>(null);
  const [editorText, setEditorText] = useState("");
  const [tags, setTags] = useState(["family", "travel"]);
  const [tagInput, setTagInput] = useState("");
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
        description="Values are resolved from the DTCG tokens in packages/design-system/tokens and drawn with the generated CSS variables. The nested previews exercise both themes."
        id="foundations"
        index="01"
        title="Foundations"
      >
        <FoundationTokens tokens={tokens} />
      </GallerySection>

      <GallerySection
        description="Shared identity and the icon set from packages/design-system/icons.json. Icon accepts name and size; BrandMark accepts className, optional counter-rotation motion, and collapsed state."
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
        <IconTokens tokens={tokens} />
      </GallerySection>

      <GallerySection
        description="PageFrame is the canonical outer geometry, sized by the layout tokens. This gallery itself uses the canvas variant."
        id="layout"
        index="03"
        title="Layout"
      >
        <LayoutTokens tokens={tokens} />
      </GallerySection>

      <GallerySection
        description="TextField, SearchField, SelectField, Checkbox, and the current production date, rich-text, occurrence, and organization editors are reusable. TextField is a proposed replacement for route-level plain text inputs; other textareas, labels, and validation messages are still route-level patterns."
        id="forms"
        index="04"
        title="Forms"
      >
        <FormControlSpecimens />

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
          api="tone · size · uppercase · one line · tags use # text"
        >
          <div className={styles.specimenCases}>
            <SpecimenCase id="badge-tones">
              {badgeTones.map((tone) => (
                <Badge key={tone} tone={tone}>
                  {tone}
                </Badge>
              ))}
            </SpecimenCase>
            <SpecimenCase id="badge-sizes">
              {badgeSizes.map((size) => (
                <Fragment key={size}>
                  <Badge size={size}>{size}</Badge>
                  <Badge size={size} uppercase>
                    {size}
                  </Badge>
                </Fragment>
              ))}
            </SpecimenCase>
            <SpecimenCase id="badge-tags">
              <Badge size="medium" title="#learning">
                #learning
              </Badge>
              <Badge size="medium" title="#旅行">
                #旅行
              </Badge>
              <Badge size="medium" tone="neutral" title="#family">
                #family
              </Badge>
            </SpecimenCase>
            <SpecimenCase id="badge-truncation">
              <div className={styles.badgeTruncationFrame}>
                <Badge title="A long label that stays on one line">
                  A long label that stays on one line
                </Badge>
                <Badge
                  size="medium"
                  title="#A long tag name that stays within the available width"
                >
                  #A long tag name that stays within the available width
                </Badge>
              </div>
            </SpecimenCase>
            <SpecimenCase id="badge-photo-overlay">
              {(["glassAccent", "glassNeutral"] as const).map((tone) => (
                <div className={styles.badgePhoto} key={tone}>
                  <ProgressiveImage alt="" src={loadedImage} />
                  <span className={styles.badgePhotoTop}>
                    <Badge size="micro" tone={tone} uppercase>
                      {tone === "glassAccent" ? "Current" : "Earlier"}
                    </Badge>
                  </span>
                  <span className={styles.badgePhotoBottom}>
                    <Badge size="micro" tone="inverse" uppercase>
                      3 photos
                    </Badge>
                  </span>
                </div>
              ))}
            </SpecimenCase>
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
          api="point · span · disabled · defaultTimezone · Day, Month, Year, Not sure"
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
        description="RecordCard is the shared interactive record surface used by Homes, Vehicles, and First Times. SeparatedList and SectionHeader organize the rows and headings around it."
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

        <Specimen
          api="title · variant: section | list · detail · detailAlign: start | end · description · action · headingLevel: 2 | 3 | 4 · headingId"
          description="The heading of a region of a page. Section is a serif title, like iOS MTSectionHeader; list is the small uppercase heading above a list, like MTListHeader. The caller chooses the heading level."
          id="section-header"
          title="SectionHeader"
        >
          <div className={styles.headerStack}>
            <div data-header="section">
              <SectionHeader headingLevel={4} title="Recent Entries" />
            </div>
            <div data-header="section-action">
              <SectionHeader
                action={
                  <a className={styles.headerLink} href="#section-header">
                    View all
                    <Icon name="chevron" size={14} />
                  </a>
                }
                headingLevel={4}
                title="A memory for today"
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
            <div data-header="list-description">
              <SectionHeader
                action={<Badge uppercase>Connected</Badge>}
                description="Your current MemoTrail identity"
                headingLevel={4}
                title="Account"
                variant="list"
              />
            </div>
            <div data-header="long">
              <SectionHeader
                action={
                  <a className={styles.headerLink} href="#section-header">
                    View all
                  </a>
                }
                detail="1,284 items"
                headingLevel={4}
                title="A long heading that wraps within its container instead of pushing the action away"
                variant="list"
              />
            </div>
          </div>
        </Specimen>
      </GallerySection>

      <GallerySection
        description="Transient action feedback and reviewed media states, including the Skeleton placeholder. The shared EmptyState is demonstrated above."
        id="feedback"
        index="06"
        title="Feedback and media states"
      >
        <div className={styles.feedbackGrid}>
          <ToastSpecimen />
          <Specimen api="completed · total" title="PhotoUploadProgress">
            <PhotoUploadProgress progress={{ completed: 3, total: 5 }} />
          </Specimen>
          <Specimen
            api="shape: fill | block | line | circle · width · height · animated"
            description="Decorative: hidden from assistive technology, so the loading region announces itself. The shimmer stops under reduced motion."
            id="skeleton"
            title="Skeleton"
          >
            <div className={styles.skeletonShapes}>
              <div data-skeleton="fill">
                <div className={styles.skeletonFrame}>
                  <Skeleton shape="fill" />
                </div>
                <small>fill</small>
              </div>
              <div data-skeleton="block">
                <Skeleton height="64px" shape="block" />
                <small>block</small>
              </div>
              <div data-skeleton="line">
                <Skeleton shape="line" />
                <Skeleton shape="line" width="72%" />
                <Skeleton shape="line" width="48%" />
                <small>line</small>
              </div>
              <div data-skeleton="circle">
                <Skeleton shape="circle" width="48px" />
                <small>circle</small>
              </div>
              <div data-skeleton="still">
                <Skeleton animated={false} height="64px" shape="block" />
                <small>animated=false</small>
              </div>
              <div data-skeleton="card">
                <div className={styles.skeletonCard}>
                  <Skeleton shape="circle" width="40px" />
                  <div>
                    <Skeleton shape="line" width="60%" />
                    <Skeleton shape="line" width="90%" />
                  </div>
                </div>
                <small>composed</small>
              </div>
            </div>
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

      <GallerySection
        description="Web-only workspace chrome. Each spec says what iOS uses instead."
        id="workspace"
        index="07"
        title="Workspace"
      >
        <WorkspaceSpecimens />
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
