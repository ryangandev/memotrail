"use client";

import { useEffect, useRef, type ReactNode } from "react";

export function SwimlaneViewport({
  children,
  className,
  firstRecordOffset,
}: {
  children: ReactNode;
  className: string;
  firstRecordOffset: number | null;
}) {
  const viewport = useRef<HTMLElement>(null);

  useEffect(() => {
    if (viewport.current && firstRecordOffset !== null) {
      viewport.current.scrollLeft = Math.max(0, firstRecordOffset - 140);
    }
  }, [firstRecordOffset]);

  return (
    <section
      aria-label="Timeline by track"
      className={className}
      ref={viewport}
    >
      {children}
    </section>
  );
}
