// Participant content locking (skeleton comparison) and the clipboard
// transforms that keep answers and answer ids out of pasted content.

import { Extension } from "@tiptap/core";
import { Plugin, PluginKey } from "prosemirror-state";
import { Slice, Fragment } from "@tiptap/pm/model";
import type { Node as PMNode } from "@tiptap/pm/model";
import { type EditorView } from "@tiptap/pm/view";
import { generateAnswerId, generatePartId } from "../ids";

// --- Participant content locking (skeleton comparison) ---------------------

// Participant mode: everything the teacher authored is read-only; only the
// answer fields accept input. Instead of enumerating every way the exam text
// could be damaged (select-all delete, paste-over, drag-drop, table commands,
// …), compare the document's *skeleton* — its full JSON with answer-field
// contents stripped and checkbox states normalized — before and after each
// transaction, and veto any transaction that changes it.
const ANSWER_CONTENT_TYPES = ["lueckentext", "answerBlock"];

type JsonNode = {
  type?: string;
  attrs?: Record<string, unknown>;
  content?: JsonNode[];
  [key: string]: unknown;
};

function stripAnswers(json: JsonNode): JsonNode {
  if (json.type && ANSWER_CONTENT_TYPES.includes(json.type)) {
    const { content, ...skeleton } = json;
    return skeleton;
  }
  // Where the pins go is the answer (a sample solution also says how many).
  if (json.type === "imagePin") {
    return { ...json, attrs: { ...json.attrs, pins: null } };
  }
  // Choosing a radio is an answer; which radios exist is not.
  if (json.type === "choice") {
    return { ...json, attrs: { ...json.attrs, checked: null } };
  }
  // Ticking a multiple-choice box is an answer; the item's label text is not.
  if (json.type === "taskItem") {
    return {
      ...json,
      attrs: { ...json.attrs, checked: null },
      content: json.content?.map(stripAnswers),
    };
  }
  if (json.content) {
    return { ...json, content: json.content.map(stripAnswers) };
  }
  return json;
}

// A selection made *inside* an answer field yields a slice whose outermost
// node is the open answerBlock/lueckentext wrapper, so pasting it would insert
// a whole new answer field (with a duplicate answerId). Strip those open
// wrappers so only the inner content travels via the clipboard. A fully
// selected answer field copied along with surrounding content appears as a
// *closed* node in the slice and is left untouched, so deliberately
// duplicating one in the content editor still works.
export function unwrapAnswerSlice(slice: Slice): Slice {
  let { content, openStart, openEnd } = slice;
  while (
    content.childCount === 1 &&
    openStart > 0 &&
    openEnd > 0 &&
    content.firstChild &&
    ANSWER_CONTENT_TYPES.includes(content.firstChild.type.name)
  ) {
    content = content.firstChild.content;
    openStart--;
    openEnd--;
  }
  if (content === slice.content) return slice;
  return new Slice(content, openStart, openEnd);
}

// Pasted content must never reuse an answerId that already exists in the
// document (copy-paste of an answer field) or twice within the pasted slice —
// colliding ids silently merge two answers in grading. Ids whose original was
// removed (cut-paste) stay unchanged so stored answers/points keep matching.
export function withFreshAnswerIds(slice: Slice, view: EditorView): Slice {
  const taken = new Set<string>();
  view.state.doc.descendants((node) => {
    if (node.attrs?.answerId != null) taken.add(String(node.attrs.answerId));
    if (node.attrs?.partId != null) taken.add(String(node.attrs.partId));
    if (node.attrs?.groupId != null) taken.add(String(node.attrs.groupId));
  });

  // Radio groups are renamed consistently across the slice: a copied table
  // row becomes a new group, but still one group, not one per radio.
  const groupRenames = new Map<string, string>();

  function mapNode(node: PMNode): PMNode {
    let attrs = node.attrs;
    if (attrs && "answerId" in attrs && attrs.answerId != null) {
      if (taken.has(String(attrs.answerId))) {
        attrs = { ...attrs, answerId: generateAnswerId() };
      }
      taken.add(String(attrs.answerId));
    }
    if (node.type.name === "choice" && attrs.groupId != null) {
      const old = String(attrs.groupId);
      if (!groupRenames.has(old)) {
        groupRenames.set(old, taken.has(old) ? generateAnswerId() : old);
      }
      const renamed = groupRenames.get(old)!;
      if (renamed !== old) attrs = { ...attrs, groupId: renamed };
    }
    // Question headings carry a partId — duplicated part ids would merge two
    // parts' points/config, so pasted copies get fresh ones too.
    if (attrs && "partId" in attrs && attrs.partId != null) {
      if (taken.has(String(attrs.partId))) {
        attrs = { ...attrs, partId: generatePartId() };
      }
      taken.add(String(attrs.partId));
    }
    const content = mapFragment(node.content);
    if (attrs === node.attrs && content === node.content) return node;
    return node.type.create(attrs, content, node.marks);
  }

  function mapFragment(fragment: Fragment): Fragment {
    let changed = false;
    const children: PMNode[] = [];
    fragment.forEach((child) => {
      const mapped = mapNode(child);
      if (mapped !== child) changed = true;
      children.push(mapped);
    });
    return changed ? Fragment.fromArray(children) : fragment;
  }

  const content = mapFragment(slice.content);
  if (content === slice.content) return slice;
  return new Slice(content, slice.openStart, slice.openEnd);
}

// ProseMirror docs are immutable, so the skeleton can be cached per doc node.
// An allowed transaction's new doc becomes the next comparison's old doc, so
// in steady state this is one stringify per keystroke.
const skeletonCache = new WeakMap<PMNode, string>();

function docSkeleton(doc: PMNode): string {
  let skeleton = skeletonCache.get(doc);
  if (skeleton === undefined) {
    skeleton = JSON.stringify(stripAnswers(doc.toJSON() as JsonNode));
    skeletonCache.set(doc, skeleton);
  }
  return skeleton;
}

export const LockExamContent = Extension.create({
  name: "lockExamContent",

  addOptions() {
    return {
      // Called when a transaction is vetoed, so the UI can explain why the
      // edit had no effect instead of leaving the editor feeling broken.
      onBlocked: null as null | (() => void),
    };
  },

  addProseMirrorPlugins() {
    const { onBlocked } = this.options;
    return [
      new Plugin({
        key: new PluginKey("lockExamContent"),
        filterTransaction(tr, state) {
          if (!tr.docChanged) return true;
          if (docSkeleton(tr.doc) === docSkeleton(state.doc)) return true;
          onBlocked?.();
          return false;
        },
      }),
    ];
  },
});
