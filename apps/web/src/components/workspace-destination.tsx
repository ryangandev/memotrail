"use client";

import Link from "next/link";
import { createContext, useContext, useLayoutEffect } from "react";
import { Icon } from "@/components/icon";
import {
  destinationLinks,
  type WorkspaceDestination,
} from "@/lib/workspace-destinations";
import styles from "./page-header.module.css";

/**
 * Lets a page tell the workspace shell which destination it belongs to when its address cannot,
 * such as an Item page, whose destination follows what the Item is.
 */
export const DeclareDestinationContext = createContext<
  ((destination: WorkspaceDestination | null) => void) | null
>(null);

/** Marks `destination` active in the workspace navigation while the calling page is shown. */
export function useDeclareDestination(destination: WorkspaceDestination) {
  const declare = useContext(DeclareDestinationContext);
  useLayoutEffect(() => {
    if (!declare) return;
    declare(destination);
    return () => declare(null);
  }, [declare, destination]);
}

/** A detail page's way back to the destination it belongs to, which it also marks active. */
export function PageBackLink({
  destination,
}: {
  destination: WorkspaceDestination;
}) {
  useDeclareDestination(destination);
  const link = destinationLinks[destination];
  return (
    <Link className={styles.back} data-page-back href={link.href}>
      <Icon name="arrowLeft" size={14} />
      {link.label}
    </Link>
  );
}
