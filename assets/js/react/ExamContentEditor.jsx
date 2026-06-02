import { Children, useCallback, useEffect, useRef, useState } from "react";
import { useEditor, EditorContent, useEditorState } from "@tiptap/react";
import { Node, Mark, Extension } from "@tiptap/core";
import { Plugin, PluginKey } from "prosemirror-state";
import StarterKit from "@tiptap/starter-kit";
import { TaskList } from "@tiptap/extension-list/task-list";
import { TaskItem } from "@tiptap/extension-list/task-item";
import { TableKit } from "@tiptap/extension-table";
import { Highlight } from "@tiptap/extension-highlight";
import { TextStyle, Color } from "@tiptap/extension-text-style";
import { Placeholder } from "@tiptap/extensions";
import Image from "@tiptap/extension-image";
import * as DropdownMenu from "@radix-ui/react-dropdown-menu";
import * as Tabs from "@radix-ui/react-tabs";
import * as Tooltip from "@radix-ui/react-tooltip";
import * as solutionEditorStore from "./solutionEditorStore";

function generateAnswerId() {
  return Math.floor(Math.random() * 9000) + 1000;
}

const answerIdAttribute = {
  answerId: {
    default: null,
    parseHTML: (el) => el.getAttribute("data-answer-id"),
    renderHTML: (attrs) =>
      attrs.answerId ? { "data-answer-id": attrs.answerId } : {},
  },
};

const Lueckentext = Node.create({
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
        ({ chain, state }) => {
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
    };
  },
});

const AnswerBlock = Node.create({
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
        ({ chain }) => {
          const answerId = generateAnswerId();
          return chain()
            .insertContent({
              type: this.name,
              attrs: { answerId },
              content: [{ type: "paragraph" }],
            })
            .run();
        },
    };
  },
});

const TaskItemWithId = TaskItem.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      ...answerIdAttribute,
    };
  },
});

const TeacherComment = Mark.create({
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
        ({ commands }) => {
          return commands.toggleMark(this.name);
        },
    };
  },
});

import {
  BoldIcon,
  ItalicIcon,
  H1Icon,
  H2Icon,
  ListBulletIcon,
  QuestionMarkCircleIcon,
  NumberedListIcon,
  ChatBubbleLeftEllipsisIcon,
  PhotoIcon,
  TableCellsIcon,
  PaintBrushIcon,
  ArrowUturnLeftIcon,
  ArrowUturnRightIcon,
} from "@heroicons/react/24/outline";

function countByType(doc, typeName) {
  let n = 0;
  doc.descendants((node) => {
    if (node.type.name === typeName) n++;
  });
  return n;
}

function findAncestorDepth($pos, typeName) {
  for (let d = $pos.depth; d > 0; d--) {
    if ($pos.node(d).type.name === typeName) return d;
  }
  return null;
}

function handleLueckentextKey(editor, direction) {
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
function collectAnswerNodes(doc) {
  const nodes = [];
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
function focusAdjacentAnswer(editor, direction) {
  const { state } = editor;
  const answers = collectAnswerNodes(state.doc);
  if (answers.length === 0) return false;

  const head = state.selection.head;
  const inside = (a) => head > a.pos && head < a.pos + a.node.nodeSize;
  const current = answers.findIndex(inside);

  let target;
  if (direction === "next") {
    target =
      current >= 0 ? answers[current + 1] : answers.find((a) => a.pos >= head);
  } else {
    target =
      current >= 0
        ? answers[current - 1]
        : answers
            .filter((a) => a.pos + a.node.nodeSize <= head)
            .pop();
  }

  // No field in that direction: let the default Tab behaviour run.
  if (!target) return false;

  // Caret just inside the end of the target's content; setTextSelection
  // resolves to the nearest valid text position.
  const pos = target.pos + target.node.nodeSize - 1;
  editor.chain().focus().setTextSelection(pos).scrollIntoView().run();
  return true;
}

const PreventNodeDeletion = Extension.create({
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

const AUTOSAVE_DELAY_MS = 1000;
// Backoff schedule for failed saves; the last entry repeats indefinitely so a
// student with flaky Wi-Fi keeps retrying until the exam ends.
const RETRY_DELAYS_MS = [2000, 4000, 8000, 15000];
// HTTP statuses where retrying can never succeed (submitted / exam ended /
// rejected payload) — give up instead of hammering the server.
const PERMANENT_SAVE_ERRORS = [400, 404, 409, 422];

const HIGHLIGHT_COLORS = [
  { name: "Rot", value: "#fecaca" },
  { name: "Orange", value: "#fed7aa" },
  { name: "Gelb", value: "#fef08a" },
  { name: "Grün", value: "#bbf7d0" },
  { name: "Blau", value: "#bfdbfe" },
  { name: "Lila", value: "#e9d5ff" },
];

// "Rot" is intentionally omitted — red is reserved for sample-solution model
// answers (rendered red automatically), so teachers can't pick it for content.
const TEXT_COLORS = [
  { name: "Orange", value: "#ea580c" },
  { name: "Gelb", value: "#ca8a04" },
  { name: "Grün", value: "#16a34a" },
  { name: "Blau", value: "#2563eb" },
  { name: "Lila", value: "#9333ea" },
];

function TextColorIcon({ className }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M6 19 L12 5 L18 19" />
      <path d="M8.5 14 H15.5" />
    </svg>
  );
}

function FreitextIcon({ className }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <text
        x="2"
        y="18"
        fontFamily="Fraunces, serif"
        fontStyle="italic"
        fontWeight="500"
        fontSize="18"
        fill="currentColor"
        stroke="none"
      >
        A
      </text>
      <path d="M13 9h8M13 13h8M13 17h5" />
    </svg>
  );
}

function FreitextAbcIcon({ className }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <text
        x="3"
        y="16"
        fontFamily="Fraunces, serif"
        fontStyle="italic"
        fontWeight="400"
        fontSize="15"
        fill="currentColor"
        stroke="none"
      >
        abc
      </text>
      <path d="M3 20h14" strokeWidth="1.4" opacity="0.5" />
    </svg>
  );
}

function LueckentextIcon({ className }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M3 10h4M17 10h4" />
      <rect
        x="9"
        y="7"
        width="6"
        height="6"
        rx="1"
        fill="currentColor"
        opacity="0.18"
        stroke="none"
      />
      <rect x="9" y="7" width="6" height="6" rx="1" />
      <path d="M3 17h18" opacity="0.4" />
    </svg>
  );
}

function MultipleChoiceIcon({ className }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <circle cx="6" cy="7" r="2.2" />
      <circle cx="6" cy="17" r="2.2" />
      <circle cx="6" cy="17" r="0.8" fill="currentColor" stroke="none" />
      <path d="M11 7h9M11 17h9" />
    </svg>
  );
}

function AddRowAboveIcon({ className }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="3" y="10" width="18" height="10" rx="1.5" />
      <line x1="3" y1="15" x2="21" y2="15" />
      <line x1="9" y1="10" x2="9" y2="20" />
      <line x1="15" y1="10" x2="15" y2="20" />
      <path d="M12 3v5" strokeWidth="1.8" />
      <path d="M9.5 5.5L12 3l2.5 2.5" strokeWidth="1.8" />
    </svg>
  );
}

function AddRowBelowIcon({ className }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="3" y="4" width="18" height="10" rx="1.5" />
      <line x1="3" y1="9" x2="21" y2="9" />
      <line x1="9" y1="4" x2="9" y2="14" />
      <line x1="15" y1="4" x2="15" y2="14" />
      <path d="M12 21v-5" strokeWidth="1.8" />
      <path d="M9.5 18.5L12 21l2.5-2.5" strokeWidth="1.8" />
    </svg>
  );
}

function RemoveRowIcon({ className }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="3" y="4" width="18" height="16" rx="1.5" />
      <line x1="3" y1="9.33" x2="21" y2="9.33" />
      <line x1="9" y1="4" x2="9" y2="20" />
      <line x1="15" y1="4" x2="15" y2="20" />
      <rect
        x="3"
        y="9.33"
        width="18"
        height="5.33"
        fill="currentColor"
        opacity="0.14"
        stroke="none"
      />
      <line x1="5" y1="14.66" x2="21" y2="14.66" />
      <path d="M5 12l14 0" strokeWidth="2" opacity="0.9" />
    </svg>
  );
}

function AddColumnLeftIcon({ className }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="9" y="4" width="12" height="16" rx="1.5" />
      <line x1="9" y1="9.33" x2="21" y2="9.33" />
      <line x1="9" y1="14.66" x2="21" y2="14.66" />
      <line x1="15" y1="4" x2="15" y2="20" />
      <path d="M3 12h5" strokeWidth="1.8" />
      <path d="M5.5 9.5L3 12l2.5 2.5" strokeWidth="1.8" />
    </svg>
  );
}

function AddColumnRightIcon({ className }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="3" y="4" width="12" height="16" rx="1.5" />
      <line x1="3" y1="9.33" x2="15" y2="9.33" />
      <line x1="3" y1="14.66" x2="15" y2="14.66" />
      <line x1="9" y1="4" x2="9" y2="20" />
      <path d="M21 12h-5" strokeWidth="1.8" />
      <path d="M18.5 9.5L21 12l-2.5 2.5" strokeWidth="1.8" />
    </svg>
  );
}

function RemoveColumnIcon({ className }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="3" y="4" width="18" height="16" rx="1.5" />
      <line x1="3" y1="9.33" x2="21" y2="9.33" />
      <line x1="3" y1="14.66" x2="21" y2="14.66" />
      <line x1="9" y1="4" x2="9" y2="20" />
      <line x1="15" y1="4" x2="15" y2="20" />
      <rect
        x="9"
        y="4"
        width="6"
        height="16"
        fill="currentColor"
        opacity="0.14"
        stroke="none"
      />
      <path d="M12 6v16" strokeWidth="2" opacity="0.9" />
    </svg>
  );
}

function HeaderRowIcon({ className }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="3" y="4" width="18" height="16" rx="1.5" />
      <path
        d="M3 5.5a1.5 1.5 0 0 1 1.5-1.5h15a1.5 1.5 0 0 1 1.5 1.5v3.83h-18z"
        fill="currentColor"
        opacity="0.22"
        stroke="none"
      />
      <line x1="3" y1="9.33" x2="21" y2="9.33" strokeWidth="1.8" />
      <line x1="3" y1="14.66" x2="21" y2="14.66" />
      <line x1="9" y1="9.33" x2="9" y2="20" />
      <line x1="15" y1="9.33" x2="15" y2="20" />
    </svg>
  );
}

function RemoveTableIcon({ className }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <rect x="3" y="4" width="18" height="16" rx="1.5" opacity="0.45" />
      <line x1="3" y1="9.33" x2="21" y2="9.33" opacity="0.45" />
      <line x1="3" y1="14.66" x2="21" y2="14.66" opacity="0.45" />
      <line x1="9" y1="4" x2="9" y2="20" opacity="0.45" />
      <line x1="15" y1="4" x2="15" y2="20" opacity="0.45" />
      <circle
        cx="18"
        cy="18"
        r="4.5"
        fill="var(--panel, #fff)"
        stroke="currentColor"
        strokeWidth="1.5"
      />
      <path d="M16 16l4 4M20 16l-4 4" strokeWidth="1.6" />
    </svg>
  );
}

function isEmptyDoc(doc) {
  return !doc || Object.keys(doc).length === 0;
}

export default function ExamContentEditor({
  initialContent,
  save,
  hideAnswers = false,
  correctionMode = false,
  notFullWidth = false,
  hideQuestion = false,
  editable = true,
  containerRef = null,
  solutionMode = false,
  placeholder = "",
  uploadImage = null,
  externalToolbar = false,
  partId = null,
  apiRef = null,
}) {
  const [status, setStatus] = useState("idle"); // idle | saving | saved | error
  const [errorMsg, setErrorMsg] = useState(null);
  const saveTimerRef = useRef(null);
  const retryTimerRef = useRef(null);
  const retryCountRef = useRef(0);
  const pendingDocRef = useRef(null);
  const inFlightRef = useRef(null);
  const rootRef = useRef(null);

  // Sends the pending doc to the server. The pending snapshot is only cleared
  // after a successful save — a failed request keeps it queued so nothing is
  // silently lost. Retryable failures (network, 5xx) re-flush with backoff;
  // permanent ones (submitted / exam ended) stop. Saves are serialized via
  // `inFlightRef` so an older doc can never overwrite a newer one.
  // Resolves to `true` iff no unsaved changes remain afterwards.
  const flush = useCallback(async () => {
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
    const attempt = save(doc);
    inFlightRef.current = attempt;
    try {
      await attempt;
      // Keystrokes that arrived while saving stay pending for the next flush.
      if (pendingDocRef.current === doc) pendingDocRef.current = null;
      retryCountRef.current = 0;
      setStatus("saved");
      setErrorMsg(null);
      return pendingDocRef.current === null;
    } catch (err) {
      if (PERMANENT_SAVE_ERRORS.includes(err.status)) {
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
  }, [save]);

  const scheduleSave = useCallback(
    (doc) => {
      pendingDocRef.current = doc;
      if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
      saveTimerRef.current = setTimeout(() => {
        saveTimerRef.current = null;
        flush();
      }, AUTOSAVE_DELAY_MS);
    },
    [flush],
  );

  const editor = useEditor({
    extensions: [
      StarterKit.configure({ horizontalRule: false }),
      Lueckentext,
      AnswerBlock,
      TaskList,
      TaskItemWithId.configure({ nested: true }),
      TableKit.configure({ table: { resizable: true } }),
      Highlight.configure({ multicolor: true }),
      TextStyle,
      Color,
      Image,
      ...(placeholder ? [Placeholder.configure({ placeholder })] : []),
      ...(hideAnswers ? [PreventNodeDeletion] : []),
      ...(correctionMode ? [TeacherComment] : []),
    ],
    editable: editable,
    content: isEmptyDoc(initialContent) ? "" : initialContent,
    onUpdate: ({ editor }) => {
      if (editable) scheduleSave(editor.getJSON());
    },
    onFocus: () => {
      if (externalToolbar && partId) solutionEditorStore.setActive(partId);
    },
    editorProps: {
      attributes: {
        class: "exam-editor__prose",
      },
    },
  });

  // Flush pending save on unmount and when the tab is hidden. The retry timer
  // is deliberately left alive on unmount: its closure still holds unsaved
  // content and the retried request can still succeed after the editor is gone.
  useEffect(() => {
    const onVisibility = () => {
      if (document.visibilityState === "hidden" && pendingDocRef.current) {
        if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
        flush();
      }
    };
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      document.removeEventListener("visibilitychange", onVisibility);
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

  // Listen for external "tiptap:setContent" DOM events on the container element
  useEffect(() => {
    const container = containerRef?.current;
    if (!container || !editor) return;

    const handler = (e) => {
      const newContent = e.detail;
      if (newContent) {
        editor.commands.setContent(newContent);
      }
    };

    container.addEventListener("tiptap:setContent", handler);
    return () => container.removeEventListener("tiptap:setContent", handler);
  }, [editor, containerRef]);

  // Shared-toolbar mode: register this editor in the cross-root store so the
  // single toolbar in the SolutionToolbar hook can bind to it on focus.
  useEffect(() => {
    if (!externalToolbar || !editor || !partId) return;
    solutionEditorStore.registerEditor(partId, editor);
    return () => solutionEditorStore.unregisterEditor(partId);
  }, [externalToolbar, editor, partId]);

  // Shared-toolbar mode: publish save status so the toolbar's StatusIndicator
  // reflects the active part.
  useEffect(() => {
    if (!externalToolbar || !partId) return;
    solutionEditorStore.setStatus(partId, status, errorMsg);
  }, [externalToolbar, partId, status, errorMsg]);

  // Toggle `is-stuck` on the toolbar once it sticks under the page header, so
  // it grows a shadow that detaches the chrome from the scrolling canvas.
  useEffect(() => {
    const root = rootRef.current;
    if (!editable || externalToolbar || !editor || !root) return;
    const toolbar = root.querySelector(".exam-editor__toolbar");
    if (!toolbar) return;

    const sentinel = document.createElement("div");
    sentinel.setAttribute("aria-hidden", "true");
    sentinel.style.height = "1px";
    sentinel.style.marginBottom = "-1px";
    sentinel.style.pointerEvents = "none";
    toolbar.parentNode.insertBefore(sentinel, toolbar);

    const observer = new IntersectionObserver(
      ([entry]) => {
        toolbar.classList.toggle("is-stuck", entry.intersectionRatio === 0);
      },
      { threshold: [0, 1], rootMargin: "-54px 0px 0px 0px" },
    );
    observer.observe(sentinel);

    return () => {
      observer.disconnect();
      sentinel.remove();
    };
  }, [editable, externalToolbar, editor]);

  if (!editor) return null;

  return (
    <div
      ref={rootRef}
      className={
        "exam-editor" +
        (notFullWidth ? " exam-editor--not-full-width" : "") +
        (solutionMode ? " exam-editor--solution-mode" : "")
      }
    >
      {editable && !externalToolbar && (
        <Toolbar
          editor={editor}
          status={status}
          errorMsg={errorMsg}
          hideAnswers={hideAnswers}
          correctionMode={correctionMode}
          hideQuestion={hideQuestion}
          uploadImage={uploadImage}
        />
      )}
      {externalToolbar && status === "error" && (
        <div className="exam-editor__inline-error" role="alert">
          {errorMsg || "Fehler beim Speichern"}
        </div>
      )}
      <div className="exam-editor__content">
        <div className="exam-editor__content-inner">
          <EditorContent editor={editor} />
        </div>
      </div>
    </div>
  );
}

export function Toolbar({
  editor,
  status,
  errorMsg,
  hideAnswers = false,
  correctionMode = false,
  hideQuestion = false,
  uploadImage = null,
}) {
  // Subscribe directly to editor transactions so the active-state reflects
  // selection/format changes instantly, independent of the autosave cadence.
  const active = useEditorState({
    editor,
    selector: ({ editor }) => ({
      bold: editor.isActive("bold"),
      italic: editor.isActive("italic"),
      h1: editor.isActive("heading", { level: 1 }),
      h2: editor.isActive("heading", { level: 2 }),
      h3: editor.isActive("heading", { level: 3 }),
      bulletList: editor.isActive("bulletList"),
      orderedList: editor.isActive("orderedList"),
      taskList: editor.isActive("taskList"),
      lueckentext: editor.isActive("lueckentext"),
      answerBlock: editor.isActive("answerBlock"),
      table: editor.isActive("table"),
      teacherComment: editor.isActive("teacherComment"),
      highlightColor: HIGHLIGHT_COLORS.find((c) =>
        editor.isActive("highlight", { color: c.value }),
      )?.value,
      textColor: TEXT_COLORS.find((c) =>
        editor.isActive("textStyle", { color: c.value }),
      )?.value,
      canUndo: editor.can().undo(),
      canRedo: editor.can().redo(),
    }),
  });

  const btn = (title, icon, action, isActive = false, disabled = false) => (
    <Tip label={title}>
      <button
        type="button"
        aria-label={title}
        className={"exam-editor__btn" + (isActive ? " is-active" : "")}
        onMouseDown={(e) => e.preventDefault()}
        onClick={action}
        disabled={disabled}
      >
        {icon}
      </button>
    </Tip>
  );

  const iconCls = "exam-editor__icon";

  const colorMenu = ({
    title,
    icon,
    colors,
    activeColor,
    onPick,
    onClear,
    clearLabel,
  }) => (
    <DropdownMenu.Root>
      <Tip label={title}>
        <DropdownMenu.Trigger asChild>
          <button
            type="button"
            aria-label={title}
            className={"exam-editor__btn" + (activeColor ? " is-active" : "")}
            onMouseDown={(e) => e.preventDefault()}
          >
            {icon}
            <span
              className="exam-editor__btn-bar"
              style={{ backgroundColor: activeColor || "transparent" }}
            />
          </button>
        </DropdownMenu.Trigger>
      </Tip>
      <DropdownMenu.Portal>
        <DropdownMenu.Content
          className="exam-editor__menu"
          sideOffset={4}
          align="start"
        >
          <div className="exam-editor__menu-swatches">
            {colors.map((c) => (
              <DropdownMenu.Item
                key={c.value}
                asChild
                onSelect={() => onPick(c.value)}
              >
                <button
                  type="button"
                  title={c.name}
                  aria-label={c.name}
                  className={
                    "exam-editor__swatch" +
                    (activeColor === c.value ? " is-active" : "")
                  }
                  style={{ backgroundColor: c.value }}
                />
              </DropdownMenu.Item>
            ))}
          </div>
          <DropdownMenu.Separator className="exam-editor__menu-separator" />
          <DropdownMenu.Item
            className="exam-editor__menu-item"
            onSelect={onClear}
          >
            {clearLabel}
          </DropdownMenu.Item>
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );

  const textColorMenu = colorMenu({
    title: "Textfarbe",
    icon: <TextColorIcon className={iconCls} />,
    colors: TEXT_COLORS,
    activeColor: active.textColor,
    onPick: (value) => editor.chain().focus().setColor(value).run(),
    onClear: () => editor.chain().focus().unsetColor().run(),
    clearLabel: "Farbe entfernen",
  });

  const highlightMenu = colorMenu({
    title: "Markieren",
    icon: <PaintBrushIcon className={iconCls} />,
    colors: HIGHLIGHT_COLORS,
    activeColor: active.highlightColor,
    onPick: (value) =>
      editor.chain().focus().toggleHighlight({ color: value }).run(),
    onClear: () => editor.chain().focus().unsetHighlight().run(),
    clearLabel: "Markierung entfernen",
  });

  const group = (label, children) => (
    <div className="exam-editor__group">
      <div className="exam-editor__group-btns">
        {Children.map(children, (c) => c)}
      </div>
      <span className="exam-editor__group-label">{label}</span>
    </div>
  );

  const [tab, setTab] = useState("start");

  return (
    <Tooltip.Provider delayDuration={400} skipDelayDuration={300}>
      <div className="exam-editor__toolbar">
      <Tabs.Root
        value={tab}
        onValueChange={setTab}
        className="exam-editor__tabs"
      >
        <div className="exam-editor__tabs-bar">
          <Tabs.List className="exam-editor__tabs-list">
            <Tabs.Trigger value="start" className="exam-editor__tab">
              Start
            </Tabs.Trigger>
            <Tabs.Trigger value="tabellen" className="exam-editor__tab">
              Tabellen
            </Tabs.Trigger>
            {correctionMode && (
              <Tabs.Trigger value="korrektur" className="exam-editor__tab">
                Korrektur
              </Tabs.Trigger>
            )}
          </Tabs.List>
          <StatusIndicator status={status} errorMsg={errorMsg} />
        </div>
        <Tabs.Content value="start" className="exam-editor__tab-content">
          <div className="exam-editor__toolbar-inner">
            {group("Aktionen", [
              btn(
                "Rückgängig",
                <ArrowUturnLeftIcon className={iconCls} />,
                () => editor.chain().focus().undo().run(),
                false,
                !active.canUndo,
              ),
              btn(
                "Wiederholen",
                <ArrowUturnRightIcon className={iconCls} />,
                () => editor.chain().focus().redo().run(),
                false,
                !active.canRedo,
              ),
            ])}
            {group("Schriftart", [
              btn(
                "Überschrift 1",
                <H1Icon className={iconCls} />,
                () => editor.chain().focus().toggleHeading({ level: 1 }).run(),
                active.h1,
              ),
              btn(
                "Überschrift 2",
                <H2Icon className={iconCls} />,
                () => editor.chain().focus().toggleHeading({ level: 2 }).run(),
                active.h2,
              ),
              btn(
                "Fett",
                <BoldIcon className={iconCls} />,
                () => editor.chain().focus().toggleBold().run(),
                active.bold,
              ),
              btn(
                "Kursiv",
                <ItalicIcon className={iconCls} />,
                () => editor.chain().focus().toggleItalic().run(),
                active.italic,
              ),
              textColorMenu,
              highlightMenu,
            ])}
            {group("Listen", [
              btn(
                "Aufzählung",
                <ListBulletIcon className={iconCls} />,
                () => editor.chain().focus().toggleBulletList().run(),
                active.bulletList,
              ),
              btn(
                "Nummerierte Liste",
                <NumberedListIcon className={iconCls} />,
                () => editor.chain().focus().toggleOrderedList().run(),
                active.orderedList,
              ),
            ])}
            {!hideQuestion &&
              group("Frage", [
                btn(
                  "Frage",
                  <QuestionMarkCircleIcon className={iconCls} />,
                  () => editor.chain().focus().toggleHeading({ level: 3 }).run(),
                  active.h3,
                ),
              ])}
            {!hideAnswers &&
              group("Antworten", [
                btn(
                  "Antwortfeld",
                  <FreitextAbcIcon className={iconCls} />,
                  () => editor.chain().focus().setAnswerBlock().run(),
                  active.answerBlock,
                ),
                btn(
                  "Aufgabenliste",
                  <MultipleChoiceIcon className={iconCls} />,
                  () => editor.chain().focus().toggleTaskList().run(),
                  active.taskList,
                ),
                btn(
                  "Lückentextfeld",
                  <LueckentextIcon className={iconCls} />,
                  () => editor.chain().focus().setLueckentext().run(),
                  active.lueckentext,
                ),
              ])}
            {uploadImage &&
              group("Einfügen", [
                <ImageButton
                  key="image"
                  editor={editor}
                  uploadImage={uploadImage}
                />,
              ])}
          </div>
        </Tabs.Content>
        <Tabs.Content value="tabellen" className="exam-editor__tab-content">
          <div className="exam-editor__toolbar-inner">
            {group("Tabelle", [
              btn(
                "Tabelle einfügen",
                <TableCellsIcon className={iconCls} />,
                () =>
                  editor
                    .chain()
                    .focus()
                    .insertTable({ rows: 3, cols: 3, withHeaderRow: true })
                    .run(),
              ),
              btn(
                "Kopfzeile umschalten",
                <HeaderRowIcon className={iconCls} />,
                () => editor.chain().focus().toggleHeaderRow().run(),
                false,
                !active.table,
              ),
              btn(
                "Tabelle löschen",
                <RemoveTableIcon className={iconCls} />,
                () => editor.chain().focus().deleteTable().run(),
                false,
                !active.table,
              ),
            ])}
            {group("Zeilen", [
              btn(
                "Zeile darüber einfügen",
                <AddRowAboveIcon className={iconCls} />,
                () => editor.chain().focus().addRowBefore().run(),
                false,
                !active.table,
              ),
              btn(
                "Zeile darunter einfügen",
                <AddRowBelowIcon className={iconCls} />,
                () => editor.chain().focus().addRowAfter().run(),
                false,
                !active.table,
              ),
              btn(
                "Zeile löschen",
                <RemoveRowIcon className={iconCls} />,
                () => editor.chain().focus().deleteRow().run(),
                false,
                !active.table,
              ),
            ])}
            {group("Spalten", [
              btn(
                "Spalte davor einfügen",
                <AddColumnLeftIcon className={iconCls} />,
                () => editor.chain().focus().addColumnBefore().run(),
                false,
                !active.table,
              ),
              btn(
                "Spalte danach einfügen",
                <AddColumnRightIcon className={iconCls} />,
                () => editor.chain().focus().addColumnAfter().run(),
                false,
                !active.table,
              ),
              btn(
                "Spalte löschen",
                <RemoveColumnIcon className={iconCls} />,
                () => editor.chain().focus().deleteColumn().run(),
                false,
                !active.table,
              ),
            ])}
          </div>
        </Tabs.Content>
        {correctionMode && (
          <Tabs.Content value="korrektur" className="exam-editor__tab-content">
            <div className="exam-editor__toolbar-inner">
              {group("Anmerkungen", [
                btn(
                  "Lehrerkommentar",
                  <ChatBubbleLeftEllipsisIcon className={iconCls} />,
                  () => editor.chain().focus().toggleTeacherComment().run(),
                  active.teacherComment,
                ),
              ])}
              {group("Bewertung", [
                btn(
                  "Falsch",
                  <span className="exam-editor__emoji" aria-hidden="true">
                    ❌
                  </span>,
                  () => editor.chain().focus().insertContent("❌").run(),
                ),
                btn(
                  "Richtig",
                  <span className="exam-editor__emoji" aria-hidden="true">
                    ✅
                  </span>,
                  () => editor.chain().focus().insertContent("✅").run(),
                ),
              ])}
            </div>
          </Tabs.Content>
        )}
      </Tabs.Root>
      </div>
    </Tooltip.Provider>
  );
}

const IS_MAC =
  typeof navigator !== "undefined" &&
  /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent || "");

// Keyboard shortcuts shown in tooltips. These mirror the Tiptap / StarterKit
// defaults for the corresponding commands.
const SHORTCUTS = {
  Rückgängig: "Mod-Z",
  Wiederholen: "Mod-Shift-Z",
  "Überschrift 1": "Mod-Alt-1",
  "Überschrift 2": "Mod-Alt-2",
  Fett: "Mod-B",
  Kursiv: "Mod-I",
  Markieren: "Mod-Shift-H",
  Aufzählung: "Mod-Shift-8",
  "Nummerierte Liste": "Mod-Shift-7",
  Frage: "Mod-Alt-3",
  Aufgabenliste: "Mod-Shift-9",
};

function formatShortcut(combo) {
  if (!combo) return null;
  return combo
    .split("-")
    .map((part) => {
      if (part === "Mod") return IS_MAC ? "⌘" : "Ctrl";
      if (part === "Shift") return IS_MAC ? "⇧" : "Shift";
      if (part === "Alt") return IS_MAC ? "⌥" : "Alt";
      return part.toUpperCase();
    })
    .join(IS_MAC ? "" : "+");
}

function ImageButton({ editor, uploadImage }) {
  const inputRef = useRef(null);
  const [uploading, setUploading] = useState(false);

  const onPick = async (e) => {
    const file = e.target.files?.[0];
    e.target.value = ""; // allow re-picking the same file
    if (!file) return;
    setUploading(true);
    try {
      const { url } = await uploadImage(file);
      editor.chain().focus().setImage({ src: url }).run();
    } catch (err) {
      console.error("Bild-Upload fehlgeschlagen", err);
      window.alert(err.message || "Bild-Upload fehlgeschlagen");
    } finally {
      setUploading(false);
    }
  };

  return (
    <>
      <Tip label="Bild einfügen">
        <button
          type="button"
          aria-label="Bild einfügen"
          className="exam-editor__btn"
          onMouseDown={(e) => e.preventDefault()}
          onClick={() => inputRef.current?.click()}
          disabled={uploading}
        >
          <PhotoIcon className="exam-editor__icon" />
        </button>
      </Tip>
      <input
        ref={inputRef}
        type="file"
        accept="image/png,image/jpeg,image/gif,image/webp"
        style={{ display: "none" }}
        onChange={onPick}
      />
    </>
  );
}

function Tip({ label, children }) {
  const shortcut = formatShortcut(SHORTCUTS[label]);
  return (
    <Tooltip.Root>
      <Tooltip.Trigger asChild>{children}</Tooltip.Trigger>
      <Tooltip.Portal>
        <Tooltip.Content
          className="exam-editor__tooltip"
          side="bottom"
          sideOffset={6}
        >
          {label}
          {shortcut && <span className="exam-editor__tooltip-kbd">{shortcut}</span>}
          <Tooltip.Arrow className="exam-editor__tooltip-arrow" />
        </Tooltip.Content>
      </Tooltip.Portal>
    </Tooltip.Root>
  );
}

function StatusIndicator({ status, errorMsg }) {
  if (status !== "error") return null;
  return (
    <div className="exam-editor__status exam-editor__status--error" role="alert">
      <span className="exam-editor__status-label">
        {errorMsg || "Fehler beim Speichern"}
      </span>
    </div>
  );
}
