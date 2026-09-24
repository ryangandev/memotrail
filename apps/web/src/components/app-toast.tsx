"use client";

import { Toaster, toast } from "sonner";
import styles from "./app-toast.module.css";

export function AppToaster() {
  return (
    <Toaster
      closeButton
      duration={4500}
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

export const notify = {
  success: (message: string) => toast.success(message),
  error: (message: string) => toast.error(message, { duration: 8000 }),
  info: (message: string) => toast.info(message),
};
