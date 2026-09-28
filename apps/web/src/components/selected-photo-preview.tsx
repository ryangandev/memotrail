"use client";

import { useEffect, useState } from "react";
import { PhotoPreviewDialog } from "@/components/photo-preview-dialog";
import { ProgressiveImage } from "@/components/progressive-image";
import styles from "./selected-photo-preview.module.css";

type PreviewState =
  | { file: File; status: "loading"; url: null }
  | { file: File; status: "ready"; url: string }
  | { file: File; status: "failed"; url: null };

export function SelectedPhotoPreview({
  alt,
  file,
}: {
  alt: string;
  file: File;
}) {
  const [preview, setPreview] = useState<PreviewState>({
    file,
    status: "loading",
    url: null,
  });
  const [openFile, setOpenFile] = useState<File | null>(null);
  const currentPreview =
    preview.file === file ? preview : { status: "loading" as const, url: null };

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
          setPreview({ file, status: "ready", url: previewUrl });
        }
      } catch {
        if (!controller.signal.aborted) {
          setPreview({ file, status: "failed", url: null });
        }
      }
    }

    void preparePreview();
    return () => {
      controller.abort();
      if (previewUrl) URL.revokeObjectURL(previewUrl);
    };
  }, [file]);

  if (currentPreview.status === "ready") {
    return (
      <>
        <button
          aria-label={`Preview selected ${file.name}`}
          className={styles.trigger}
          data-photo-preview-trigger
          onClick={() => setOpenFile(file)}
          type="button"
        >
          <ProgressiveImage alt={alt} src={currentPreview.url} />
        </button>
        {openFile === file ? (
          <PhotoPreviewDialog
            name={file.name}
            onClose={() => setOpenFile(null)}
            src={currentPreview.url}
          />
        ) : null}
      </>
    );
  }

  return (
    <span
      aria-busy={currentPreview.status === "loading"}
      className={styles.placeholder}
      role="status"
    >
      {currentPreview.status === "loading"
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
