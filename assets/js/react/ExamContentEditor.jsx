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
import * as DropdownMenu from "@radix-ui/react-dropdown-menu";
import * as Tabs from "@radix-ui/react-tabs";

const Lueckentext = Node.create({
  name: "lueckentext",
  inline: true,
  group: "inline",
  content: "inline*",

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
          if (text) {
            return chain()
              .deleteSelection()
              .insertContent({
                type: this.name,
                content: [{ type: "text", text }],
              })
              .run();
          }
          return chain().insertContent({ type: this.name }).run();
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
    return {
      answerId: {
        default: null,
        parseHTML: (el) => el.getAttribute("data-answer-id"),
        renderHTML: (attrs) =>
          attrs.answerId ? { "data-answer-id": attrs.answerId } : {},
      },
    };
  },

  parseHTML() {
    return [{ tag: "div.answer-block" }];
  },

  renderHTML({ HTMLAttributes }) {
    return ["div", { ...HTMLAttributes, class: "answer-block" }, 0];
  },

  addCommands() {
    return {
      setAnswerBlock:
        () =>
        ({ chain }) => {
          const answerId = Math.floor(Math.random() * 9000) + 1000;
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

const PageBreak = Node.create({
  name: "pageBreak",
  group: "block",
  atom: true,
  selectable: true,
  draggable: false,

  addAttributes() {
    return {
      pageId: {
        default: null,
        parseHTML: (el) => el.getAttribute("data-page-id"),
        renderHTML: (attrs) =>
          attrs.pageId ? { "data-page-id": attrs.pageId } : {},
      },
    };
  },

  parseHTML() {
    return [{ tag: "div.page-break" }];
  },

  renderHTML({ HTMLAttributes }) {
    return ["div", { ...HTMLAttributes, class: "page-break" }];
  },

  addCommands() {
    return {
      setPageBreak:
        () =>
        ({ commands }) => {
          const pageId = Math.floor(Math.random() * 90000000) + 10000000;
          return commands.insertContent({
            type: this.name,
            attrs: { pageId },
          });
        },
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
  H3Icon,
  ListBulletIcon,
  NumberedListIcon,
  ChatBubbleBottomCenterTextIcon,
  ChatBubbleLeftEllipsisIcon,
  MinusIcon,
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
  if (depth === null) return false;

  const node = $from.node(depth);
  const nodeStart = $from.start(depth);
  const nodeEnd = $from.end(depth);

  if (empty) {
    // Cursor at boundary — block so we don't exit / remove the node
    if (direction === "backspace" && $from.parentOffset === 0) return true;
    if (direction === "delete" && $from.parentOffset === node.content.size)
      return true;

    // Deleting the last remaining character — clear content, keep node
    if (node.content.size === 1) {
      editor.view.dispatch(state.tr.delete(nodeStart, nodeEnd));
      return true;
    }
  } else {
    // Non-empty selection: if it covers ALL content, clear manually
    const selFrom = selection.from;
    const selTo = selection.to;
    if (selFrom <= nodeStart && selTo >= nodeEnd) {
      editor.view.dispatch(state.tr.delete(nodeStart, nodeEnd));
      return true;
    }
  }

  return false;
}

const PreventNodeDeletion = Extension.create({
  name: "preventNodeDeletion",

  addKeyboardShortcuts() {
    return {
      Backspace: ({ editor }) => handleLueckentextKey(editor, "backspace"),
      Delete: ({ editor }) => handleLueckentextKey(editor, "delete"),
    };
  },

  addProseMirrorPlugins() {
    const protectedTypes = ["lueckentext", "answerBlock", "pageBreak"];
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

const HIGHLIGHT_COLORS = [
  { name: "Rot", value: "#fecaca" },
  { name: "Orange", value: "#fed7aa" },
  { name: "Gelb", value: "#fef08a" },
  { name: "Grün", value: "#bbf7d0" },
  { name: "Blau", value: "#bfdbfe" },
  { name: "Lila", value: "#e9d5ff" },
];

const TEXT_COLORS = [
  { name: "Rot", value: "#dc2626" },
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
  hidePageBreak = false,
  editable = true,
  containerRef = null,
}) {
  const [status, setStatus] = useState("idle"); // idle | saving | saved | error
  const [errorMsg, setErrorMsg] = useState(null);
  const saveTimerRef = useRef(null);
  const pendingDocRef = useRef(null);

  const flush = useCallback(async () => {
    const doc = pendingDocRef.current;
    if (!doc) return;
    pendingDocRef.current = null;
    setStatus("saving");
    setErrorMsg(null);
    try {
      await save(doc);
      setStatus("saved");
    } catch (err) {
      setStatus("error");
      setErrorMsg(err.message || "Speichern fehlgeschlagen");
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
      PageBreak,
      Lueckentext,
      AnswerBlock,
      TaskList,
      TaskItem.configure({ nested: true }),
      TableKit.configure({ table: { resizable: true } }),
      Highlight.configure({ multicolor: true }),
      TextStyle,
      Color,
      ...(hideAnswers ? [PreventNodeDeletion] : []),
      ...(correctionMode ? [TeacherComment] : []),
    ],
    editable: editable,
    content: isEmptyDoc(initialContent) ? "" : initialContent,
    onUpdate: ({ editor }) => {
      if (editable) scheduleSave(editor.getJSON());
    },
    editorProps: {
      attributes: {
        class: "exam-editor__prose",
      },
    },
  });

  // Flush pending save on unmount and when the tab is hidden.
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

  if (!editor) return null;

  return (
    <div
      className={
        "exam-editor" + (notFullWidth ? " exam-editor--not-full-width" : "")
      }
    >
      {editable && (
        <Toolbar
          editor={editor}
          status={status}
          errorMsg={errorMsg}
          hideAnswers={hideAnswers}
          correctionMode={correctionMode}
          hidePageBreak={hidePageBreak}
        />
      )}
      <div className="exam-editor__content">
        <div className="exam-editor__content-inner">
          <EditorContent editor={editor} />
        </div>
      </div>
    </div>
  );
}

function Toolbar({
  editor,
  status,
  errorMsg,
  hideAnswers = false,
  correctionMode = false,
  hidePageBreak = false,
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
      blockquote: editor.isActive("blockquote"),
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
    <button
      type="button"
      title={title}
      aria-label={title}
      className={"exam-editor__btn" + (isActive ? " is-active" : "")}
      onMouseDown={(e) => e.preventDefault()}
      onClick={action}
      disabled={disabled}
    >
      {icon}
    </button>
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
      <DropdownMenu.Trigger asChild>
        <button
          type="button"
          title={title}
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
            {group("Überschriften", [
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
                "Überschrift 3",
                <H3Icon className={iconCls} />,
                () => editor.chain().focus().toggleHeading({ level: 3 }).run(),
                active.h3,
              ),
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
            {!hideAnswers &&
              group("Antworten", [
                btn(
                  "Lückentextfeld",
                  <LueckentextIcon className={iconCls} />,
                  () => editor.chain().focus().setLueckentext().run(),
                  active.lueckentext,
                ),
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
                  "Zitat",
                  <ChatBubbleBottomCenterTextIcon className={iconCls} />,
                  () => editor.chain().focus().toggleBlockquote().run(),
                  active.blockquote,
                ),
              ])}
            {!correctionMode &&
              !hidePageBreak &&
              group("Struktur", [
                btn("Seitenumbruch", <MinusIcon className={iconCls} />, () =>
                  editor.chain().focus().setPageBreak().run(),
                ),
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
  );
}

function StatusIndicator({ status, errorMsg }) {
  const isError = status === "error";
  const dotTitle =
    status === "saving"
      ? "Speichert..."
      : isError
        ? errorMsg || "Fehler beim Speichern"
        : "Gespeichert";
  const dotCls =
    "exam-editor__status-dot" +
    (status === "saving" ? " exam-editor__status-dot--saving" : "") +
    (isError ? " exam-editor__status-dot--error" : "");
  return (
    <div
      className={
        "exam-editor__status" + (isError ? " exam-editor__status--error" : "")
      }
    >
      <span
        className={dotCls}
        title={dotTitle}
        aria-label={dotTitle}
        role="status"
      />
      {isError && (
        <span className="exam-editor__status-label">
          {errorMsg || "Fehler beim Speichern"}
        </span>
      )}
    </div>
  );
}
