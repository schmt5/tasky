// The exam editor's binding to the autosave engine (../../autosave.ts): one
// engine per mounted editor, its status mirrored into React state, and the
// imperative flush API used by the submit-modal handshake.

import { useEffect, useRef, useState, type MutableRefObject } from "react";

import { createAutosave, type AutosaveEngine } from "../../autosave";
import type { SaveFn, SaveStatus, TiptapDoc } from "./types";

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

  // The engine outlives re-renders; it always calls the latest `save`.
  const saveRef = useRef(save);
  saveRef.current = save;

  const engineRef = useRef<AutosaveEngine<TiptapDoc> | null>(null);
  if (engineRef.current === null) {
    engineRef.current = createAutosave<TiptapDoc>(
      (doc, opts) => saveRef.current(doc, opts),
      (nextStatus, nextError) => {
        setStatus(nextStatus);
        setErrorMsg(nextError);
      },
    );
  }
  const engine = engineRef.current;

  // Flush pending save on unmount (and drop the page listeners).
  useEffect(() => () => engine.destroy(), [engine]);

  // Imperative API for the surrounding LiveView hook (guest exam submit flow):
  // lets it force-flush before submission and clean up once submitted.
  useEffect(() => {
    if (!apiRef) return;
    apiRef.current = {
      flush: engine.flush,
      hasUnsavedChanges: engine.hasUnsavedChanges,
      suspendAutosave: engine.suspend,
    };
    return () => {
      apiRef.current = null;
    };
  }, [apiRef, engine]);

  return {
    status,
    errorMsg,
    scheduleSave: engine.schedule,
    flush: engine.flush,
  };
}
