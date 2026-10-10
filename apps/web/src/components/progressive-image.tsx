"use client";

import {
  useEffect,
  useRef,
  useState,
  type ImgHTMLAttributes,
  type ReactNode,
} from "react";
import { Skeleton } from "./skeleton";
import styles from "./progressive-image.module.css";

type ImageStatus = "loading" | "loaded" | "failed";

type ProgressiveImageProps = Omit<
  ImgHTMLAttributes<HTMLImageElement>,
  "children" | "onError" | "onLoad"
> & {
  fallback?: ReactNode;
  fit?: "contain" | "cover";
};

export function ProgressiveImage({
  alt,
  className,
  decoding = "async",
  fallback,
  fit = "cover",
  src,
  ...props
}: ProgressiveImageProps) {
  const imageRef = useRef<HTMLImageElement>(null);
  const [imageState, setImageState] = useState<{
    src: typeof src;
    status: ImageStatus;
  }>({ src, status: "loading" });
  const status = imageState.src === src ? imageState.status : "loading";

  useEffect(() => {
    const image = imageRef.current;

    if (!src || !image?.complete) return;

    const settledStatus = image.naturalWidth > 0 ? "loaded" : "failed";
    setImageState((current) =>
      current.src === src && current.status === settledStatus
        ? current
        : { src, status: settledStatus },
    );
  }, [src]);

  return (
    <span
      aria-busy={status === "loading"}
      className={`${styles.frame} ${className ?? ""}`}
      data-image-status={status}
    >
      <Skeleton
        animated={status === "loading"}
        className={styles.skeleton}
        shape="fill"
      />
      {/* Private, expiring, already optimized media grants bypass the public Next image cache. */}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        {...props}
        alt={alt}
        className={`${styles.image} ${styles[fit]}`}
        decoding={decoding}
        onError={() => setImageState({ src, status: "failed" })}
        onLoad={() => setImageState({ src, status: "loaded" })}
        ref={imageRef}
        src={src}
      />
      {status === "failed" ? (
        <span className={styles.fallback} role="status">
          {fallback ?? "Photo unavailable"}
        </span>
      ) : null}
    </span>
  );
}
