import type { PhotoUploadProgress as Progress } from "@/lib/media/upload";
import styles from "./photo-upload-progress.module.css";

export function PhotoUploadProgress({ progress }: { progress: Progress }) {
  const percentage =
    progress.total > 0
      ? Math.round((progress.completed / progress.total) * 100)
      : 0;
  return (
    <div
      aria-label="Photo upload progress"
      aria-valuemax={progress.total}
      aria-valuemin={0}
      aria-valuenow={progress.completed}
      className={styles.progress}
      role="progressbar"
    >
      <span>
        Uploading photos {progress.completed} of {progress.total}
      </span>
      <span aria-hidden="true" className={styles.track}>
        <span style={{ width: `${percentage}%` }} />
      </span>
    </div>
  );
}
