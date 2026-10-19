"use client";

import { Fragment, useState } from "react";
import { BrandMark } from "@/components/brand-mark";
import { Badge } from "@/components/badge";
import { EntryOrganizationEditor } from "@/components/entry-organization-editor";
import { EntryPhotoField } from "@/components/entry-photo-field";
import { OccurrenceEditor } from "@/components/occurrence-editor";
import { ProgressiveImage } from "@/components/progressive-image";
import { badgeSizes, badgeTones } from "@/generated/design-system";
import type { OccurrenceDraft } from "@/lib/data/occurrence";
import styles from "./page.module.css";
import {
  CaptureComposerSpecimen,
  RecordCardSpecimen,
  RichTextSpecimen,
  SectionHeaderSpecimen,
  SeparatedListSpecimen,
} from "./content-specimens";
import {
  ImageSpecimen,
  PhotoViewerSpecimen,
  SkeletonSpecimen,
  UploadProgressSpecimen,
} from "./media-specimens";
import { loadedImage } from "./samples";
import { SharedPrimitivesGallery } from "./shared-primitives-gallery";
import { ToastSpecimen, WorkspaceSpecimens } from "./controls-gallery";
import { FormControlSpecimens } from "./form-controls-gallery";
import { BrandMotionPreview } from "./brand-motion-preview";
import { EntryRowSpecimen } from "./entry-row-specimen";
import {
  FoundationTokens,
  IconTokens,
  LayoutTokens,
  type TokenSet,
} from "./foundations-gallery";
import { Specimen, SpecimenCase } from "./specimen";

export function DesignSystemGallery({ tokens }: { tokens: TokenSet }) {
  const [galleryTheme, setGalleryTheme] = useState<"system" | "light" | "dark">(
    "system",
  );
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
        description="TextField, SearchField, SelectField, Checkbox, SegmentedControl, and the current production date, rich-text, occurrence, and organization editors are reusable. TextField is a proposed replacement for route-level plain text inputs; other textareas, labels, and validation messages are still route-level patterns."
        id="forms"
        index="04"
        title="Forms"
      >
        <FormControlSpecimens />

        <RichTextSpecimen />

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
              options={["family", "travel", "first-time", "work"]}
            />
          </div>
        </Specimen>

        <Specimen
          api="span · disabled · defaultTimezone · Day, Month, Year, Not sure"
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
        description="EntryRow lists Entries, and RecordCard is the shared interactive card that the native First Times grid uses. SeparatedList and SectionHeader organize the rows and headings around them, and CaptureComposer writes new Entries."
        id="containers"
        index="05"
        title="Containers and data display"
      >
        <RecordCardSpecimen />
        <EntryRowSpecimen />
        <SeparatedListSpecimen />
        <SectionHeaderSpecimen />
        <CaptureComposerSpecimen />
      </GallerySection>

      <GallerySection
        description="Transient action feedback and reviewed media states, including the Skeleton placeholder. The shared EmptyState is demonstrated above."
        id="feedback"
        index="06"
        title="Feedback and media states"
      >
        <div className={styles.feedbackGrid}>
          <ToastSpecimen />
          <UploadProgressSpecimen />
          <SkeletonSpecimen />
          <ImageSpecimen />
          <PhotoViewerSpecimen />
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
