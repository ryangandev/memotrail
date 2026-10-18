import type { ReactNode } from "react";
import { EmptyState } from "@/components/empty-state";
import { Icon } from "@/components/icon";
import { PageFrame } from "@/components/page-frame";

/**
 * What a route shows in place of its page when it cannot: a calm message and
 * the next step, inside the workspace shell where there is one.
 */
export function RouteFallback({
  actions,
  description,
  icon,
  title,
}: {
  actions: ReactNode;
  description: ReactNode;
  icon: "refresh" | "search";
  title: ReactNode;
}) {
  return (
    <PageFrame variant="compact">
      <EmptyState
        actions={actions}
        description={description}
        icon={<Icon name={icon} size={25} />}
        title={title}
      />
    </PageFrame>
  );
}
