// The autosave engine, framework-free: debounced scheduling, serialized
// flushes, retry-with-backoff for transient failures (and at once when the
// browser comes back online), permanent-failure classification (session
// expiry, submitted exam), unload-safe keepalive flushes and the imperative
// flush used by the submit-modal handshake.
//
// Two front ends drive it: `useAutosave` (the Tiptap editors) and the
// `ExamAnswersForm` hook (the learner's native answer fields).

import {
  AUTOSAVE_DELAY_MS,
  DISCARD_SAVE_ERRORS,
  MAX_RETRIES_AFTER_DESTROY,
  RETRY_DELAYS_MS,
  PERMANENT_SAVE_ERRORS,
} from "./react/editor/constants";
import type { SaveError, SaveOpts, SaveStatus } from "./react/editor/types";

export type PayloadSaveFn<T> = (payload: T, opts?: SaveOpts) => Promise<unknown>;

export interface AutosaveEngine<T> {
  schedule: (payload: T) => void;
  /** Resolves to `true` iff no unsaved changes remain afterwards. */
  flush: (opts?: { unload?: boolean }) => Promise<boolean>;
  hasUnsavedChanges: () => boolean;
  /** Drops everything pending — for when saving can no longer succeed. */
  suspend: () => void;
  /**
   * Removes the page listeners and flushes what is pending. The retry timer
   * is deliberately left alive: its closure still holds unsaved content and
   * the retried request can still succeed after the editor is gone — but
   * only for `MAX_RETRIES_AFTER_DESTROY` more attempts, not forever.
   */
  destroy: () => void;
}

export function createAutosave<T>(
  save: PayloadSaveFn<T>,
  onStatus: (status: SaveStatus, errorMsg: string | null) => void,
): AutosaveEngine<T> {
  let saveTimer: ReturnType<typeof setTimeout> | null = null;
  let retryTimer: ReturnType<typeof setTimeout> | null = null;
  let retryCount = 0;
  let retriesAfterDestroy = 0;
  let destroyed = false;
  let pending: T | null = null;
  let inFlight: Promise<unknown> | null = null;

  // Sends the pending payload. It is only cleared after a successful save — a
  // failed request keeps it queued so nothing is silently lost. Retryable
  // failures (network, 5xx) re-flush with backoff; permanent ones (submitted /
  // exam ended) stop. Saves are serialized via `inFlight` so an older payload
  // can never overwrite a newer one.
  async function flush({ unload = false }: { unload?: boolean } = {}): Promise<boolean> {
    while (inFlight) {
      try {
        await inFlight;
      } catch {
        // Failure handling belongs to the flush that started the request.
      }
    }

    const payload = pending;
    if (payload === null) return true;
    if (retryTimer) {
      clearTimeout(retryTimer);
      retryTimer = null;
    }
    onStatus("saving", null);
    // keepalive lets the request outlive a closing tab (unload-time flush).
    const attempt = save(payload, unload ? { keepalive: true } : {});
    inFlight = attempt;
    try {
      await attempt;
      // Input that arrived while saving stays pending for the next flush.
      if (pending === payload) pending = null;
      retryCount = 0;
      onStatus("saved", null);
      return pending === null;
    } catch (error) {
      const err = error as SaveError;

      if (err.permanent || PERMANENT_SAVE_ERRORS.includes(err.status ?? 0)) {
        // No retry either way. Only a submission that can never take the
        // changes again drops them; otherwise they stay pending, so the page
        // keeps warning before it closes and the next edit tries once more.
        if (DISCARD_SAVE_ERRORS.includes(err.status ?? 0)) pending = null;
        onStatus("error", err.message || "Speichern nicht mehr möglich");
      } else if (destroyed && retriesAfterDestroy >= MAX_RETRIES_AFTER_DESTROY) {
        // Nobody is looking at this editor any more; stop knocking.
        pending = null;
      } else {
        const delay =
          RETRY_DELAYS_MS[Math.min(retryCount, RETRY_DELAYS_MS.length - 1)];
        retryCount += 1;
        if (destroyed) retriesAfterDestroy += 1;
        onStatus("error", "Speichern fehlgeschlagen – versuche erneut …");
        retryTimer = setTimeout(() => {
          retryTimer = null;
          flush();
        }, delay);
      }
      return false;
    } finally {
      if (inFlight === attempt) inFlight = null;
    }
  }

  function schedule(payload: T) {
    pending = payload;
    if (saveTimer) clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      saveTimer = null;
      flush();
    }, AUTOSAVE_DELAY_MS);
  }

  // Hidden-tab flushes use keepalive so the request survives the tab closing,
  // and beforeunload warns while changes are still unsaved.
  const onVisibility = () => {
    if (document.visibilityState === "hidden" && pending !== null) {
      if (saveTimer) clearTimeout(saveTimer);
      flush({ unload: true });
    }
  };
  const onBeforeUnload = (e: BeforeUnloadEvent) => {
    if (pending !== null || inFlight) {
      e.preventDefault();
      e.returnValue = "";
    }
  };
  // Back online: retry now instead of sitting out the rest of the backoff.
  const onOnline = () => {
    if (retryTimer) flush();
  };
  document.addEventListener("visibilitychange", onVisibility);
  window.addEventListener("beforeunload", onBeforeUnload);
  window.addEventListener("online", onOnline);

  return {
    schedule,
    flush,
    hasUnsavedChanges: () => pending !== null || inFlight !== null,
    suspend: () => {
      if (saveTimer) clearTimeout(saveTimer);
      if (retryTimer) clearTimeout(retryTimer);
      saveTimer = null;
      retryTimer = null;
      pending = null;
    },
    destroy: () => {
      destroyed = true;
      document.removeEventListener("visibilitychange", onVisibility);
      window.removeEventListener("beforeunload", onBeforeUnload);
      window.removeEventListener("online", onOnline);
      if (saveTimer) clearTimeout(saveTimer);
      saveTimer = null;
      if (pending !== null) flush();
    },
  };
}
