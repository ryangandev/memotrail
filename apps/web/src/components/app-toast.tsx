"use client";

import { Toaster, toast } from "sonner";
import { durations, type ToastTone } from "@/generated/design-system";
import styles from "./app-toast.module.css";

/**
 * Where toasts appear: the bottom right, at most three at a time. The workspace renders one
 * without an id; a Toaster with an id shows only the toasts sent to it, as the design-system
 * gallery's stages do. Specified in packages/design-system/components/toast.yaml.
 */
export function AppToaster({
  expand = false,
  id,
}: {
  /** Lays every visible toast out in full instead of stacking the older ones. */
  expand?: boolean;
  id?: string;
} = {}) {
  return (
    <Toaster
      closeButton
      duration={durations.toast}
      expand={expand}
      id={id}
      position="bottom-right"
      visibleToasts={3}
      toastOptions={{
        unstyled: true,
        classNames: {
          toast: styles.toast,
          content: styles.content,
          title: styles.title,
          description: styles.description,
          icon: styles.icon,
          closeButton: styles.closeButton,
        },
      }}
    />
  );
}

/**
 * Shows a toast in a tone, for as long as the tone's motion token says unless a duration is
 * given. Sonner owns the toast element, so the message carries the spec's data-ui marker.
 */
export function showToast(
  tone: ToastTone,
  message: string,
  options: { duration?: number; id?: string; toasterId?: string } = {},
) {
  return toast[tone](
    <span data-tone={tone} data-ui-toast>
      {message}
    </span>,
    {
      duration:
        options.duration ??
        (tone === "error" ? durations.toastError : durations.toast),
      id: options.id,
      toasterId: options.toasterId,
    },
  );
}

export const notify = {
  success: (message: string) => showToast("success", message),
  error: (message: string) => showToast("error", message),
  info: (message: string) => showToast("info", message),
} satisfies Record<ToastTone, (message: string) => unknown>;
