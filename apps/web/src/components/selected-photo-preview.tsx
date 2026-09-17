"use client";

import { useEffect, useState } from "react";
import { ProgressiveImage } from "@/components/progressive-image";
import styles from "./selected-photo-preview.module.css";

type PreviewState =
  | { status: "loading"; url: null }
  | { status: "ready"; url: string }
  | { status: "failed"; url: null };

export function SelectedPhotoPreview({
  alt,
  file,
}: {
  alt: string;
  file: File;
}) {
  const [preview, setPreview] = useState<PreviewState>({
    status: "loading",
    url: null,
  });

  useEffect(() => {
    const controller = new AbortController();
    let previewUrl: string | null = null;

    async function preparePreview() {
      try {
        if (!needsServerPreview(file)) {
          previewUrl = URL.createObjectURL(file);
        } else {
          const formData = new FormData();
          formData.set("photo", file);
          const response = await fetch("/api/media/preview", {
            body: formData,
            method: "POST",
            signal: controller.signal,
          });
          if (!response.ok) throw new Error("Preview unavailable");
          previewUrl = URL.createObjectURL(await response.blob());
        }
        if (!controller.signal.aborted) {
          setPreview({ status: "ready", url: previewUrl });
        }
      } catch {
        if (!controller.signal.aborted) {
          setPreview({ status: "failed", url: null });
        }
      }
    }

    void preparePreview();
    return () => {
      controller.abort();
      if (previewUrl) URL.revokeObjectURL(previewUrl);
    };
  }, [file]);

  if (preview.status === "ready") {
    return <ProgressiveImage alt={alt} src={preview.url} />;
  }

  return (
    <span
      aria-busy={preview.status === "loading"}
      className={styles.placeholder}
      role="status"
    >
      {preview.status === "loading"
        ? "Preparing preview..."
        : "Preview unavailable. Photo is still selected."}
    </span>
  );
}

function needsServerPreview(file: File) {
  return (
    file.type === "image/heic" ||
    file.type === "image/heif" ||
    /\.(heic|heif)$/i.test(file.name)
  );
}
