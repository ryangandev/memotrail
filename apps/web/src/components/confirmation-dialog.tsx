"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { Button } from "./button";
import { Dialog } from "./dialog";

type ConfirmationRequest = {
  title: ReactNode;
  description: ReactNode;
  confirmLabel: string;
  cancelLabel?: string;
  eyebrow?: ReactNode;
  variant?: "primary" | "danger";
};

type RequestConfirmation = (request: ConfirmationRequest) => Promise<boolean>;

const ConfirmationContext = createContext<RequestConfirmation | null>(null);

export function ConfirmationDialogProvider({
  children,
}: {
  children: ReactNode;
}) {
  const [request, setRequest] = useState<ConfirmationRequest | null>(null);
  const resolver = useRef<((confirmed: boolean) => void) | null>(null);

  const finish = useCallback((confirmed: boolean) => {
    resolver.current?.(confirmed);
    resolver.current = null;
    setRequest(null);
  }, []);

  const requestConfirmation = useCallback<RequestConfirmation>(
    (nextRequest) => {
      resolver.current?.(false);
      setRequest(nextRequest);
      return new Promise<boolean>((resolve) => {
        resolver.current = resolve;
      });
    },
    [],
  );

  useEffect(
    () => () => {
      resolver.current?.(false);
      resolver.current = null;
    },
    [],
  );

  return (
    <ConfirmationContext value={requestConfirmation}>
      {children}
      {request ? (
        <Dialog
          open
          size="compact"
          title={request.title}
          description={request.description}
          eyebrow={request.eyebrow ?? <>Please confirm</>}
          closeLabel="Close confirmation"
          onOpenChange={(open) => {
            if (!open) finish(false);
          }}
          footer={
            <>
              <Button
                data-autofocus
                onClick={() => finish(false)}
                type="button"
                variant="secondary"
              >
                {request.cancelLabel ?? "Cancel"}
              </Button>
              <Button
                onClick={() => finish(true)}
                type="button"
                variant={request.variant ?? "primary"}
              >
                {request.confirmLabel}
              </Button>
            </>
          }
        />
      ) : null}
    </ConfirmationContext>
  );
}

export function useConfirmationDialog() {
  const requestConfirmation = useContext(ConfirmationContext);
  if (!requestConfirmation) {
    throw new Error(
      "useConfirmationDialog must be used within ConfirmationDialogProvider",
    );
  }
  return requestConfirmation;
}
