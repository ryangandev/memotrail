import { ButtonLink } from "@/components/button";
import { PageFrame } from "@/components/page-frame";
import { PageHeader } from "@/components/page-header";

export function FocusedDetailUnavailable({
  label,
  back,
}: {
  label: string;
  back: string;
}) {
  return (
    <PageFrame variant="compact">
      <PageHeader
        eyebrow={label}
        title={`${label} unavailable`}
        description="This record may have moved to Trash or no longer be accessible."
      />
      <ButtonLink href={back}>
        Back to {back.slice(1).replace("-", " ")}
      </ButtonLink>
    </PageFrame>
  );
}
