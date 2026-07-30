// The autosave engine of the exam editor: debounced scheduling, serialized
// flushes, retry-with-backoff for transient failures, permanent-failure
// classification (session expiry, submitted exam), unload-safe keepalive
// flushes and the imperative flush API used by the submit-modal handshake.

import { useCallback, useEffect, useRef, useState, type MutableRefObject } from "react";

import {
  AUTOSAVE_DELAY_MS,
  RETRY_DELAYS_MS,
  PERMANENT_SAVE_ERRORS,
} from "./constants";
import type { SaveError, SaveFn, SaveStatus, TiptapDoc } from "./types";

export interface EditorApi {
  flush: (opts?: { unload?: boolean }) => Promise<boolean>;
  hasUnsavedChanges: () => boolean;
  suspendAutosave: () => void;
}

export interface Autosave {
  status: SaveStatus;
  errorMsg: string | null;
  scheduleSave: (doc: TiptapDoc) => void;
  flush: (opts?: { unload?: boolean }) => Promise<boolean>;
}

export function useAutosave(
  save: SaveFn,
  apiRef?: MutableRefObject<EditorApi | null> | null,
): Autosave {
  const [status, setStatus] = useState<SaveStatus>("idle");
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const retryTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const retryCountRef = useRef(0);
  const pendingDocRef = useRef<TiptapDoc | null>(null);
  const inFlightRef = useRef<Promise<unknown> | null>(null);

  // Sends the pending doc to the server. The pending snapshot is only cleared
  // after a successful save — a failed request keeps it queued so nothing is
  // silently lost. Retryable failures (network, 5xx) re-flush with backoff;
  // permanent ones (submitted / exam ended) stop. Saves are serialized via
  // `inFlightRef` so an older doc can never overwrite a newer one.
  // Resolves to `true` iff no unsaved changes remain afterwards.
  const flush = useCallback(
    async ({ unload = false }: { unload?: boolean } = {}): Promise<boolean> => {
      while (inFlightRef.current) {
        try {
          await inFlightRef.current;
        } catch {
          // Failure handling belongs to the flush that started the request.
        }
      }

      const doc = pendingDocRef.current;
      if (!doc) return true;
      if (retryTimerRef.current) {
        clearTimeout(retryTimerRef.current);
        retryTimerRef.current = null;
      }
      setStatus("saving");
      // keepalive lets the request outlive a closing tab (unload-time flush).
      const attempt = save(doc, unload ? { keepalive: true } : {});
      inFlightRef.current = attempt;
      try {
        await attempt;
        // Keystrokes that arrived while saving stay pending for the next flush.
        if (pendingDocRef.current === doc) pendingDocRef.current = null;
        retryCountRef.current = 0;
        setStatus("saved");
        setErrorMsg(null);
        return pendingDocRef.current === null;
      } catch (error) {
        const err = error as SaveError;

        if (err.permanent || PERMANENT_SAVE_ERRORS.includes(err.status ?? 0)) {
          pendingDocRef.current = null;
          setStatus("error");
          setErrorMsg(err.message || "Speichern nicht mehr möglich");
        } else {
          const delay =
            RETRY_DELAYS_MS[
              Math.min(retryCountRef.current, RETRY_DELAYS_MS.length - 1)
            ];
          retryCountRef.current += 1;
          setStatus("error");
          setErrorMsg("Speichern fehlgeschlagen – versuche erneut …");
          retryTimerRef.current = setTimeout(() => {
            retryTimerRef.current = null;
            flush();
          }, delay);
        }
        return false;
      } finally {
        if (inFlightRef.current === attempt) inFlightRef.current = null;
      }
    },
    [save],
  );

  const scheduleSave = useCallback(
    (doc: TiptapDoc) => {
      pendingDocRef.current = doc;
      if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
      saveTimerRef.current = setTimeout(() => {
        saveTimerRef.current = null;
        flush();
      }, AUTOSAVE_DELAY_MS);
    },
    [flush],
  );

  // Flush pending save on unmount and when the tab is hidden. The retry timer
  // is deliberately left alive on unmount: its closure still holds unsaved
  // content and the retried request can still succeed after the editor is gone.
  // Hidden-tab flushes use keepalive so the request survives the tab closing,
  // and beforeunload warns while changes are still unsaved.
  useEffect(() => {
    const onVisibility = () => {
      if (document.visibilityState === "hidden" && pendingDocRef.current) {
        if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
        flush({ unload: true });
      }
    };
    const onBeforeUnload = (e: BeforeUnloadEvent) => {
      if (pendingDocRef.current || inFlightRef.current) {
        e.preventDefault();
        e.returnValue = "";
      }
    };
    document.addEventListener("visibilitychange", onVisibility);
    window.addEventListener("beforeunload", onBeforeUnload);
    return () => {
      document.removeEventListener("visibilitychange", onVisibility);
      window.removeEventListener("beforeunload", onBeforeUnload);
      if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
      if (pendingDocRef.current) flush();
    };
  }, [flush]);

  // Imperative API for the surrounding LiveView hook (guest exam submit flow):
  // lets it force-flush before submission and clean up once submitted.
  useEffect(() => {
    if (!apiRef) return;
    apiRef.current = {
      flush,
      hasUnsavedChanges: () =>
        pendingDocRef.current !== null || inFlightRef.current !== null,
      suspendAutosave: () => {
        if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
        if (retryTimerRef.current) clearTimeout(retryTimerRef.current);
        saveTimerRef.current = null;
        retryTimerRef.current = null;
        pendingDocRef.current = null;
      },
    };
    return () => {
      apiRef.current = null;
    };
  }, [apiRef, flush]);

  return { status, errorMsg, scheduleSave, flush };
}
