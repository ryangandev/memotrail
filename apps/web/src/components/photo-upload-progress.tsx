import type { CSSProperties } from "react";
import {
  uploadProgressDefaults,
  type UploadProgressVariant,
} from "@/generated/design-system";
import type { PhotoUploadProgress as Progress } from "@/lib/media/upload";
import styles from "./photo-upload-progress.module.css";

/**
 * Batch photo upload progress as a ring, counting finished files rather than bytes.
 * Specified in packages/design-system/components/upload-progress.yaml.
 */
export function PhotoUploadProgress({
  progress,
  variant = uploadProgressDefaults.variant,
}: {
  progress: Progress;
  variant?: UploadProgressVariant;
}) {
  const percentage =
    progress.total > 0
      ? Math.min(
          100,
          Math.max(0, Math.round((progress.completed / progress.total) * 100)),
        )
      : 0;
  return (
    <div
      aria-label="Photo upload progress"
      aria-valuemax={progress.total}
      aria-valuemin={0}
      aria-valuenow={progress.completed}
      aria-valuetext={`${progress.completed} of ${progress.total} photos, ${percentage}%`}
      className={`${styles.progress} ${
        variant === "overlay" ? styles.overlay : ""
      }`}
      data-ui-upload-progress
      data-variant={variant}
      role="progressbar"
    >
      <span
        aria-hidden="true"
        className={styles.ring}
        style={
          { "--upload-progress": `${percentage * 3.6}deg` } as CSSProperties
        }
      >
        <strong>{percentage}%</strong>
      </span>
      {variant === "inline" ? (
        <span className={styles.copy}>
          <strong>Uploading photos</strong>
          <small>
            {progress.completed} of {progress.total}
          </small>
        </span>
      ) : null}
    </div>
  );
}
