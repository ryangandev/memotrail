"use client";

import { useState } from "react";
import { Button } from "@/components/button";
import { Icon } from "@/components/icon";
import { PhotoPreviewDialog } from "@/components/photo-preview-dialog";
import { PhotoUploadProgress } from "@/components/photo-upload-progress";
import { ProgressiveImage } from "@/components/progressive-image";
import { Skeleton } from "@/components/skeleton";
import { imageFits, skeletonShapes } from "@/generated/design-system";
import styles from "./page.module.css";
import { homePhotos, loadedImage, tallImage } from "./samples";
import { Specimen, SpecimenCase } from "./specimen";

// The media and loading specimens, in the order of the iOS gallery's feedback section.

export function UploadProgressSpecimen() {
  const [completed, setCompleted] = useState(3);
  const progress = { completed, total: 5 };
  return (
    <Specimen
      api="progress: completed · total · variant: inline | overlay"
      description="Counts finished files, not uploaded bytes."
      id="upload-progress"
      title="UploadProgress"
    >
      <div className={styles.specimenCases}>
        <SpecimenCase id="upload-progress-inline">
          <PhotoUploadProgress progress={progress} />
        </SpecimenCase>
        <SpecimenCase id="upload-progress-overlay">
          <div className={styles.uploadTile}>
            <ProgressiveImage alt="" src={loadedImage} />
            <PhotoUploadProgress progress={progress} variant="overlay" />
          </div>
        </SpecimenCase>
        <div>
          <Button
            onClick={() =>
              setCompleted((value) => (value >= 5 ? 0 : value + 1))
            }
            size="small"
            variant="secondary"
          >
            <Icon name="refresh" size={14} />
            Advance upload
          </Button>
        </div>
      </div>
    </Specimen>
  );
}

export function ImageSpecimen() {
  return (
    <Specimen
      api="ProgressiveImage · src · alt · fit: cover | contain · fallback"
      description="Loading is normally brief while the photo downloads. Failure replaces the shimmer with the fallback."
      id="image"
      title="Image"
    >
      <div className={styles.specimenCases}>
        <SpecimenCase id="image-states">
          <div className={styles.imageStates}>
            <figure>
              <ProgressiveImage alt="Coast" src={loadedImage} />
              <figcaption>Loaded</figcaption>
            </figure>
            <figure>
              <span aria-busy="true" aria-label="Loading photo" role="img">
                <Skeleton shape="fill" />
              </span>
              <figcaption>Loading</figcaption>
            </figure>
            <figure>
              <ProgressiveImage
                alt="Unavailable photo"
                src="/design-system/intentionally-missing-image.png"
              />
              <figcaption>Failed</figcaption>
            </figure>
          </div>
        </SpecimenCase>
        <SpecimenCase id="image-fit">
          <div className={styles.imageStates}>
            {imageFits.map((fit) => (
              <figure key={fit}>
                <ProgressiveImage alt="Lighthouse" fit={fit} src={tallImage} />
                <figcaption>{fit}</figcaption>
              </figure>
            ))}
          </div>
        </SpecimenCase>
      </div>
    </Specimen>
  );
}

export function SkeletonSpecimen() {
  return (
    <Specimen
      api="shape: fill | block | line | circle · animated · width · height"
      description="Decorative: hidden from assistive technology, so the loading region announces itself. The shimmer stops under reduced motion."
      id="skeleton"
      title="Skeleton"
    >
      <div className={styles.specimenCases}>
        <SpecimenCase id="skeleton-shapes">
          <div className={styles.skeletonShapes}>
            {skeletonShapes.map((shape) => (
              <div data-skeleton={shape} key={shape}>
                {shape === "fill" ? (
                  <div className={styles.skeletonFrame}>
                    <Skeleton shape="fill" />
                  </div>
                ) : (
                  <Skeleton shape={shape} />
                )}
                <small>{shape}</small>
              </div>
            ))}
          </div>
        </SpecimenCase>
        <SpecimenCase id="skeleton-still">
          <div className={styles.skeletonStack} data-skeleton="still">
            <Skeleton animated={false} />
            <Skeleton animated={false} shape="line" />
            <Skeleton animated={false} shape="line" width="240px" />
          </div>
        </SpecimenCase>
        <SpecimenCase id="skeleton-composed">
          <div className={styles.skeletonStack} data-skeleton="composed">
            <div className={styles.skeletonRow}>
              <Skeleton shape="circle" />
              <div className={styles.skeletonStack}>
                <Skeleton shape="line" width="160px" />
                <Skeleton shape="line" />
              </div>
            </div>
            <Skeleton />
          </div>
        </SpecimenCase>
      </div>
    </Specimen>
  );
}

export function PhotoViewerSpecimen() {
  const [selected, setSelected] = useState<number | null>(null);
  const photo = selected === null ? null : homePhotos[selected];
  return (
    <Specimen
      api="PhotoPreviewDialog · name · src · position · onPrevious · onNext · onClose"
      description="Selecting a saved photo opens it whole in a wide dialog."
      id="photo-viewer"
      title="PhotoViewer"
    >
      <SpecimenCase id="photo-viewer-paged">
        <Button
          data-specimen-open
          onClick={() => setSelected(1)}
          variant="secondary"
        >
          <Icon name="photo" size={16} />
          Open photo viewer
        </Button>
        {photo ? (
          <PhotoPreviewDialog
            name={photo.name}
            onClose={() => setSelected(null)}
            onNext={() => setSelected((index) => (index ?? 0) + 1)}
            onPrevious={() => setSelected((index) => (index ?? 0) - 1)}
            position={{ index: selected!, total: homePhotos.length }}
            src={photo.src}
          />
        ) : null}
      </SpecimenCase>
    </Specimen>
  );
}
