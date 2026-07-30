// The two contracts the editor shares with the server (see
// docs/ROBUSTNESS_PLAN.md 4.6): the Tiptap document JSON shape stored in the
// DB, and the autosave API payloads.

/** One node of the stored Tiptap document. */
export interface TiptapNode {
  type: string;
  attrs?: {
    /** Stable id on answer-bearing nodes (answerBlock, lueckentext, taskItem). */
    answerId?: string | number | null;
    /** Stable id on question headings (h3). */
    partId?: string | null;
    level?: number;
    checked?: boolean | null;
    [key: string]: unknown;
  };
  content?: TiptapNode[];
  marks?: Array<{ type: string; attrs?: Record<string, unknown> }>;
  text?: string;
}

/** The stored document: always `{type: "doc", content: [...]}`. */
export interface TiptapDoc {
  type: "doc";
  content?: TiptapNode[];
}

/** Fetch options forwarded by the save functions (unload-time keepalive). */
export interface SaveOpts {
  keepalive?: boolean;
}

/**
 * The autosave contract: full-document endpoints receive `{content: doc}`,
 * per-part endpoints receive `{nodes: doc.content}` — both via a SaveFn the
 * hook wires up (see assets/js/react/api.js).
 */
export type SaveFn = (doc: TiptapDoc, opts?: SaveOpts) => Promise<unknown>;

/** Save lifecycle surfaced in the status pill. */
export type SaveStatus = "idle" | "saving" | "saved" | "error";

/** Error shape thrown by api.js `request` — status plus permanence flag. */
export interface SaveError extends Error {
  status?: number;
  permanent?: boolean;
}
