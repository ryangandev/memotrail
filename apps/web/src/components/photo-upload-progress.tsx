import type { CSSProperties } from "react";
import type { PhotoUploadProgress as Progress } from "@/lib/media/upload";
import styles from "./photo-upload-progress.module.css";

export function PhotoUploadProgress({
  progress,
  variant = "inline",
}: {
  progress: Progress;
  variant?: "inline" | "overlay";
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
