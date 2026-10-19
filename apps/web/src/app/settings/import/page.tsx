import { ImportWorkspace } from "@/components/import-workspace";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { latestJobView, progressOf } from "@/lib/import/jobs";
import { importMaxZipBytes } from "@/lib/import/limits";
import type { ImportJobView, ImportProgress } from "@/lib/import/contracts";
import type { ImportSource } from "@/lib/import/types";

export const dynamic = "force-dynamic";

// The sources whose adapters are installed. A source is offered only when it can be read.
const availableSources: ImportSource[] = ["markdown", "apple_notes"];

export default async function ImportPage() {
  const context = await getAuthenticatedContext();
  if (!context) return null;
  let job: ImportJobView | null = null;
  let progress: ImportProgress | null = null;
  let failed = false;
  try {
    job = await latestJobView(context.client);
    progress = job ? await progressOf(context.client, job.id) : null;
  } catch {
    failed = true;
  }
  return (
    <ImportWorkspace
      availableSources={availableSources}
      initialError={failed}
      initialJob={job}
      initialProgress={progress}
      maxBytes={importMaxZipBytes()}
    />
  );
}
