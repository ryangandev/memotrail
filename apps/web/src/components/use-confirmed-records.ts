"use client";

import { useState } from "react";

// Keep successful saves usable while the route refresh still contains older props.
// Revision acknowledgement releases the override so future remote edits win.
export function useConfirmedRecords<T extends { id: string; revision: number }>(
  server: T[],
) {
  const [confirmed, setConfirmed] = useState<Map<string, T>>(() => new Map());
  const [previous, setPrevious] = useState(server);
  if (previous !== server) {
    setPrevious(server);
    setConfirmed((current) => {
      const next = new Map(current);
      for (const record of server) {
        const saved = next.get(record.id);
        if (saved && record.revision >= saved.revision) next.delete(record.id);
      }
      return next.size === current.size ? current : next;
    });
  }
  const records = new Map(server.map((record) => [record.id, record]));
  for (const saved of confirmed.values()) {
    if ((records.get(saved.id)?.revision ?? -1) < saved.revision)
      records.set(saved.id, saved);
  }
  return {
    records: [...records.values()],
    confirm: (record: T) =>
      setConfirmed((current) => new Map(current).set(record.id, record)),
    forget: (id: string) =>
      setConfirmed((current) => {
        const next = new Map(current);
        next.delete(id);
        return next;
      }),
  };
}
