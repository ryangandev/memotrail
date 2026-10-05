import { ButtonLink } from "@/components/button";
import { PageFrame } from "@/components/page-frame";
import { PageHeader } from "@/components/page-header";

export function FocusedDetailUnavailable({
  label,
  back,
  backLabel,
}: {
  label: string;
  back: string;
  backLabel: string;
}) {
  return (
    <PageFrame variant="compact">
      <PageHeader
        actions={<ButtonLink href={back}>Back to {backLabel}</ButtonLink>}
        eyebrow={label}
        title={`${label} unavailable`}
        description="This record may have moved to Trash or no longer be accessible."
      />
    </PageFrame>
  );
}
