"use client";

import { useState, type ReactNode } from "react";
import Image from "next/image";

export function RecordCardMap({
  eager = false,
  fallback,
  latitude,
  longitude,
}: {
  eager?: boolean;
  fallback: ReactNode;
  latitude: number | null | undefined;
  longitude: number | null | undefined;
}) {
  const [failedSource, setFailedSource] = useState<string | null>(null);
  const source =
    typeof latitude === "number" &&
    Number.isFinite(latitude) &&
    latitude >= -90 &&
    latitude <= 90 &&
    typeof longitude === "number" &&
    Number.isFinite(longitude) &&
    longitude >= -180 &&
    longitude <= 180
      ? `/api/locations/map?lat=${latitude}&lon=${longitude}&card=1`
      : null;

  if (!source || failedSource === source) return <>{fallback}</>;

  return (
    <Image
      alt=""
      data-record-card-map="true"
      height={280}
      loading={eager ? "eager" : "lazy"}
      onError={() => setFailedSource(source)}
      src={source}
      unoptimized
      width={720}
    />
  );
}
