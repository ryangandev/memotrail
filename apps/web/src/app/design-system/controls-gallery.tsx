"use client";

import { useEffect, useState } from "react";
import { AppToaster, notify, showToast } from "@/components/app-toast";
import { Button } from "@/components/button";
import { CommandPalette } from "@/components/command-palette";
import { Icon } from "@/components/icon";
import { SyncStatusButton } from "@/components/sync-status";
import { WorkspaceActionDock } from "@/components/workspace-action-dock";
import { toastTones, type ToastTone } from "@/generated/design-system";
import captureStyles from "@/components/quick-capture-dialog.module.css";
import dockStyles from "@/components/workspace-action-dock.module.css";
import styles from "./page.module.css";
import controls from "./controls-gallery.module.css";
import { Specimen, SpecimenCase } from "./specimen";

const toneMessages: Record<ToastTone, string> = {
  success: "Entry saved.",
  info: "Pending Entry discarded.",
  error: "Could not move to Trash. Try again.",
};

/** Shows the given toasts in a gallery toaster that keeps them until they are closed. */
function useStaticToasts(
  toasterId: string,
  toasts: readonly (readonly [ToastTone, string])[],
) {
  useEffect(() => {
    // Stable ids keep a remount, or Strict Mode's second effect, from adding duplicates.
    toasts.forEach(([tone, message], index) =>
      showToast(tone, message, {
        duration: Infinity,
        id: `${toasterId}-${index}`,
        toasterId,
      }),
    );
  }, [toasterId, toasts]);
}

const toneToasts = toastTones.map(
  (tone) => [tone, toneMessages[tone]] as const,
);
const longToast = [
  [
    "error",
    "Could not upload 3 photos. They stay on this device and upload when MemoTrail can be reached.",
  ],
] as const;

/**
 * Toast, from packages/design-system/components/toast.yaml. The static specimens draw in their own
 * toasters inside a stage; the buttons send live toasts to the workspace toaster.
 */
export function ToastSpecimen() {
  useStaticToasts("gallery-toast-tones", toneToasts);
  useStaticToasts("gallery-toast-long", longToast);
  return (
    <Specimen
      api="notify.success · notify.info · notify.error · showToast(tone, message)"
      title="Toast"
    >
      <div className={styles.specimenCases}>
        <SpecimenCase id="toast-tones">
          <div className={`${controls.stage} ${controls.toastStage}`}>
            <AppToaster expand id="gallery-toast-tones" />
          </div>
        </SpecimenCase>
        <SpecimenCase id="toast-long-message">
          <div className={`${controls.stage} ${controls.toastStageShort}`}>
            <AppToaster id="gallery-toast-long" />
          </div>
        </SpecimenCase>
      </div>
      <div className={`${styles.toastPreviewActions} ${controls.liveActions}`}>
        <Button onClick={() => notify.success("Changes saved.")}>
          Show success
        </Button>
        <Button
          variant="secondary"
          onClick={() => notify.info("Moved to Trash.")}
        >
          Show info
        </Button>
        <Button
          variant="danger"
          onClick={() => notify.error("Could not save. Try again.")}
        >
          Show error
        </Button>
      </div>
    </Specimen>
  );
}

/**
 * The Web-only workspace chrome: CommandPalette, SyncStatus, and WorkspaceActionDock. Their specs
 * say why iOS has none.
 */
export function WorkspaceSpecimens() {
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [message, setMessage] = useState("No workspace actions yet.");
  return (
    <>
      <Specimen
        api="open · onClose"
        description="Opens from the dock's search shortcut or Command K. Destinations navigate; a query searches the archive."
        title="CommandPalette"
      >
        <div className={styles.specimenCases}>
          <SpecimenCase id="command-palette-destinations">
            <Button
              data-specimen-open
              onClick={() => setPaletteOpen(true)}
              variant="secondary"
            >
              <Icon name="search" size={16} />
              Open command palette
            </Button>
            <CommandPalette
              onClose={() => setPaletteOpen(false)}
              open={paletteOpen}
            />
          </SpecimenCase>
        </div>
      </Specimen>
      <Specimen
        api="SyncStatus reads the capture queue · SyncStatusButton: waiting · rejected · busy"
        description="Appears in the top bar only while captures wait on this device. Pressing it syncs and lists what is waiting."
        title="SyncStatus"
      >
        <div className={styles.specimenCases}>
          <SpecimenCase id="sync-status-counts">
            <div className={controls.syncRow}>
              <SyncStatusButton
                busy={false}
                onClick={() => setMessage("Sync started for 2 captures.")}
                rejected={0}
                waiting={2}
              />
              <SyncStatusButton
                busy={false}
                onClick={() =>
                  setMessage("Review the capture MemoTrail did not accept.")
                }
                rejected={1}
                waiting={3}
              />
              <SyncStatusButton busy rejected={0} waiting={1} />
            </div>
          </SpecimenCase>
        </div>
      </Specimen>
      <Specimen
        api="children · onSearch"
        description="Fixed to the bottom of the workspace. The search shortcut also answers Command K."
        title="WorkspaceActionDock"
      >
        <div className={styles.specimenCases}>
          <SpecimenCase id="workspace-action-dock-search">
            <div className={`${controls.stage} ${controls.dockStage}`}>
              <WorkspaceActionDock onSearch={() => setPaletteOpen(true)}>
                <button
                  aria-label="New entry"
                  className={`${dockStyles.control} ${captureStyles.trigger}`}
                  onClick={() =>
                    setMessage("Quick Capture opens from this control.")
                  }
                  type="button"
                >
                  <span className={captureStyles.triggerMark}>
                    <Icon name="sparkle" size={19} />
                  </span>
                  <span className={captureStyles.triggerPrompt}>
                    What’s on your mind?
                  </span>
                  <kbd aria-hidden="true">⌘ J</kbd>
                </button>
              </WorkspaceActionDock>
            </div>
          </SpecimenCase>
        </div>
        <p className={styles.stateNote} role="status">
          {message}
        </p>
      </Specimen>
    </>
  );
}
