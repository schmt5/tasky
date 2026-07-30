// All Tiptap/ProseMirror extensions of the exam editor: the answer-bearing
// nodes, stable-id plumbing, deletion guards, participant content locking and
// the clipboard transforms. Pure editor machinery — no React in here.

import { Node, Mark, Extension, type Editor } from "@tiptap/core";
import { Heading } from "@tiptap/extension-heading";
import { TaskItem } from "@tiptap/extension-list/task-item";
import { Plugin, PluginKey } from "prosemirror-state";
import { Slice, Fragment } from "@tiptap/pm/model";
import type { Node as PMNode, ResolvedPos } from "@tiptap/pm/model";
import type { EditorView } from "@tiptap/pm/view";

import { generateAnswerId, generatePartId } from "./ids";

declare module "@tiptap/core" {
  interface Commands<ReturnType> {
    lueckentext: { setLueckentext: () => ReturnType };
    answerBlock: { setAnswerBlock: () => ReturnType };
    teacherComment: { toggleTeacherComment: () => ReturnType };
  }
}

// Question headings (h3) carry a stable partId so all part-keyed data
// (points, AI config, corrected parts) survives reordering and insertion.
export const HeadingWithPartId = Heading.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      partId: {
        default: null,
        parseHTML: (el: HTMLElement) => el.getAttribute("data-part-id"),
        renderHTML: (attrs: Record<string, unknown>) =>
          attrs.partId ? { "data-part-id": attrs.partId } : {},
      },
    };
  },
});

// Stamps a partId onto any level-3 heading that lacks one (typed headings,
// legacy docs). Only active in the content editor — locked editors can't
// create headings and their filterTransaction would veto the stamp.
export const PartIdStamper = Extension.create({
  name: "partIdStamper",

  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: new PluginKey("partIdStamper"),
        appendTransaction(transactions, _oldState, newState) {
          if (!transactions.some((tr) => tr.docChanged)) return null;

          let tr: typeof newState.tr | null = null;
          newState.doc.descendants((node, pos) => {
            if (
              node.type.name === "heading" &&
              node.attrs.level === 3 &&
              !node.attrs.partId
            ) {
              tr = tr || newState.tr;
              tr.setNodeMarkup(pos, undefined, {
                ...node.attrs,
                partId: generatePartId(),
              });
            }
          });

          return tr;
        },
      }),
    ];
  },
});

const answerIdAttribute = {
  answerId: {
    default: null,
    parseHTML: (el: HTMLElement) => el.getAttribute("data-answer-id"),
    renderHTML: (attrs: Record<string, unknown>) =>
      attrs.answerId ? { "data-answer-id": attrs.answerId } : {},
  },
};

export const Lueckentext = Node.create({
  name: "lueckentext",
  inline: true,
  group: "inline",
  content: "inline*",

  addAttributes() {
    return { ...answerIdAttribute };
  },

  parseHTML() {
    return [{ tag: "span.lueckentext" }];
  },

  renderHTML({ HTMLAttributes }) {
    return ["span", { ...HTMLAttributes, class: "lueckentext" }, 0];
  },

  addCommands() {
    return {
      setLueckentext:
        () =>
        ({ chain, state }: { chain: any; state: any }) => {
          const { from, to } = state.selection;
          const text = state.doc.textBetween(from, to);
          const attrs = { answerId: generateAnswerId() };
          if (text) {
            return chain()
              .deleteSelection()
              .insertContent({
                type: this.name,
                attrs,
                content: [{ type: "text", text }],
              })
              .run();
          }
          return chain().insertContent({ type: this.name, attrs }).run();
        },
    } as any;
  },
});

export const AnswerBlock = Node.create({
  name: "answerBlock",
  group: "block",
  content: "block+",
  defining: true,

  addAttributes() {
    return { ...answerIdAttribute };
  },

  parseHTML() {
    return [{ tag: "div.answer-block" }];
  },

  renderHTML({ HTMLAttributes }) {
    // No DOM `tabindex` here: a focusable wrapper steals browser focus on Tab
    // without moving the ProseMirror selection, desyncing the caret. Tab
    // navigation between answer fields is handled in PreventNodeDeletion.
    return ["div", { ...HTMLAttributes, class: "answer-block" }, 0];
  },

  addCommands() {
    return {
      setAnswerBlock:
        () =>
        ({ chain }: { chain: any }) => {
          const answerId = generateAnswerId();
          return chain()
            .insertContent({
              type: this.name,
              attrs: { answerId },
              content: [{ type: "paragraph" }],
            })
            .run();
        },
    } as any;
  },
});

export const TaskItemWithId = TaskItem.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      ...answerIdAttribute,
    };
  },
});

export const TeacherComment = Mark.create({
  name: "teacherComment",

  parseHTML() {
    return [{ tag: "span.teacher-comment" }];
  },

  renderHTML({ HTMLAttributes }) {
    return ["span", { ...HTMLAttributes, class: "teacher-comment" }, 0];
  },

  addCommands() {
    return {
      toggleTeacherComment:
        () =>
        ({ commands }: { commands: any }) =>
          commands.toggleMark(this.name),
    } as any;
  },
});

// --- Deletion guards & answer-field navigation -----------------------------

function countByType(doc: PMNode, typeName: string): number {
  let n = 0;
  doc.descendants((node) => {
    if (node.type.name === typeName) n++;
  });
  return n;
}

function findAncestorDepth($pos: ResolvedPos, typeName: string): number | null {
  for (let d = $pos.depth; d > 0; d--) {
    if ($pos.node(d).type.name === typeName) return d;
  }
  return null;
}

function handleLueckentextKey(
  editor: Editor,
  direction: "backspace" | "delete",
): boolean {
  const { state } = editor;
  const { selection } = state;
  const { $from, empty } = selection;

  const depth = findAncestorDepth($from, "lueckentext");

  // Cursor outside any lueckentext: let the native deletion run. It can never
  // remove a protected node — the filterTransaction plugin vetoes any edit that
  // reduces the node count — so there is nothing to block here. Blocking would
  // only stop legitimate deletion of adjacent external characters.
  if (depth === null) return false;

  const node = $from.node(depth);
  const nodeStart = $from.start(depth);
  const nodeEnd = $from.end(depth);
  const atStart = $from.parentOffset === 0;
  const atEnd = $from.parentOffset === node.content.size;

  if (empty) {
    // Deleting the node's last remaining character. Native deletion would drop
    // the now-empty inline node, which filterTransaction vetoes — leaving the
    // character "stuck". So clear the content manually and keep the node.
    // Only do this when the keystroke actually targets that character:
    // backspace deletes the char before the cursor, delete the one after.
    const deletesOnlyChar =
      node.content.size === 1 &&
      ((direction === "backspace" && !atStart) ||
        (direction === "delete" && !atEnd));
    if (deletesOnlyChar) {
      editor.view.dispatch(state.tr.delete(nodeStart, nodeEnd));
      return true;
    }
    // Everything else (deleting an interior char, or an adjacent external char
    // at a boundary) is left to native deletion; node removal stays vetoed.
    return false;
  }

  // Non-empty selection covering ALL of the node's content: clear manually so
  // the node survives (native delete would drop it and be vetoed).
  if (selection.from <= nodeStart && selection.to >= nodeEnd) {
    editor.view.dispatch(state.tr.delete(nodeStart, nodeEnd));
    return true;
  }

  return false;
}

// All answer fields (inline gaps and answer blocks) in document order.
function collectAnswerNodes(doc: PMNode): Array<{ node: PMNode; pos: number }> {
  const nodes: Array<{ node: PMNode; pos: number }> = [];
  doc.descendants((node, pos) => {
    if (node.type.name === "lueckentext" || node.type.name === "answerBlock") {
      nodes.push({ node, pos });
      return false; // don't descend into an answer field
    }
    return true;
  });
  return nodes;
}

// Tab / Shift-Tab navigation between answer fields. Moves the ProseMirror
// selection (and DOM focus, via .focus()) into the next/previous field so the
// caret and focus ring stay in sync — unlike a DOM `tabindex`, which moves only
// the focus ring and leaves the caret behind.
function focusAdjacentAnswer(editor: Editor, direction: "next" | "prev") {
  const { state } = editor;
  const answers = collectAnswerNodes(state.doc);
  if (answers.length === 0) return false;

  const head = state.selection.head;
  const inside = (a: { node: PMNode; pos: number }) =>
    head > a.pos && head < a.pos + a.node.nodeSize;
  const current = answers.findIndex(inside);

  let target;
  if (direction === "next") {
    target =
      current >= 0 ? answers[current + 1] : answers.find((a) => a.pos >= head);
  } else {
    target =
      current >= 0
        ? answers[current - 1]
        : answers.filter((a) => a.pos + a.node.nodeSize <= head).pop();
  }

  // No field in that direction: let the default Tab behaviour run.
  if (!target) return false;

  // Caret just inside the end of the target's content; setTextSelection
  // resolves to the nearest valid text position.
  const pos = target.pos + target.node.nodeSize - 1;
  editor.chain().focus().setTextSelection(pos).scrollIntoView().run();
  return true;
}

export const PreventNodeDeletion = Extension.create({
  name: "preventNodeDeletion",

  addKeyboardShortcuts() {
    return {
      Backspace: ({ editor }) => handleLueckentextKey(editor, "backspace"),
      Delete: ({ editor }) => handleLueckentextKey(editor, "delete"),
      Tab: ({ editor }) => focusAdjacentAnswer(editor, "next"),
      "Shift-Tab": ({ editor }) => focusAdjacentAnswer(editor, "prev"),
    };
  },

  addProseMirrorPlugins() {
    const protectedTypes = ["lueckentext", "answerBlock"];
    return [
      new Plugin({
        key: new PluginKey("preventNodeDeletion"),
        filterTransaction(tr, state) {
          if (!tr.docChanged) return true;
          for (const t of protectedTypes) {
            if (countByType(tr.doc, t) < countByType(state.doc, t)) {
              return false;
            }
          }
          return true;
        },
      }),
    ];
  },
});

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
  });

  function mapNode(node: PMNode): PMNode {
    let attrs = node.attrs;
    if (attrs && "answerId" in attrs && attrs.answerId != null) {
      if (taken.has(String(attrs.answerId))) {
        attrs = { ...attrs, answerId: generateAnswerId() };
      }
      taken.add(String(attrs.answerId));
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
