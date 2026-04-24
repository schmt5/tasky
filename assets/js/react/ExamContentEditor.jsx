import { Children, useCallback, useEffect, useRef, useState } from "react";
import { useEditor, EditorContent, useEditorState } from "@tiptap/react";
import { Node } from "@tiptap/core";
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
          const pageId = Math.floor(Math.random() * 9000) + 1000;
          return commands.insertContent({
            type: this.name,
            attrs: { pageId },
          });
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
  CodeBracketIcon,
  CodeBracketSquareIcon,
  MinusIcon,
  CheckCircleIcon,
  TableCellsIcon,
  TrashIcon,
  ViewColumnsIcon,
  Bars3Icon,
  PaintBrushIcon,
  ArrowLongUpIcon,
  ArrowLongDownIcon,
  ArrowLongLeftIcon,
  ArrowLongRightIcon,
} from "@heroicons/react/24/outline";
import { saveExamContent } from "./api";

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

function isEmptyDoc(doc) {
  return !doc || Object.keys(doc).length === 0;
}

export default function ExamContentEditor({ examId, initialContent }) {
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
      await saveExamContent(examId, doc);
      setStatus("saved");
    } catch (err) {
      setStatus("error");
      setErrorMsg(err.message || "Speichern fehlgeschlagen");
    }
  }, [examId]);

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
    ],
    content: isEmptyDoc(initialContent) ? "" : initialContent,
    onUpdate: ({ editor }) => {
      scheduleSave(editor.getJSON());
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

  if (!editor) return null;

  return (
    <div className="exam-editor">
      <Toolbar editor={editor} status={status} errorMsg={errorMsg} />
      <div className="exam-editor__content">
        <div className="exam-editor__content-inner">
          <EditorContent editor={editor} />
        </div>
      </div>
    </div>
  );
}

function Toolbar({ editor, status, errorMsg }) {
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
      highlightColor: HIGHLIGHT_COLORS.find((c) =>
        editor.isActive("highlight", { color: c.value }),
      )?.value,
      textColor: TEXT_COLORS.find((c) =>
        editor.isActive("textStyle", { color: c.value }),
      )?.value,
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
    onPick: (value) =>
      editor.chain().focus().setColor(value).run(),
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

  useEffect(() => {
    setTab(active.table ? "tabellen" : "start");
  }, [active.table]);

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
          </Tabs.List>
          <StatusIndicator status={status} errorMsg={errorMsg} />
        </div>
        <Tabs.Content value="start" className="exam-editor__tab-content">
          <div className="exam-editor__toolbar-inner">
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
                () =>
                  editor.chain().focus().toggleHeading({ level: 1 }).run(),
                active.h1,
              ),
              btn(
                "Überschrift 2",
                <H2Icon className={iconCls} />,
                () =>
                  editor.chain().focus().toggleHeading({ level: 2 }).run(),
                active.h2,
              ),
              btn(
                "Überschrift 3",
                <H3Icon className={iconCls} />,
                () =>
                  editor.chain().focus().toggleHeading({ level: 3 }).run(),
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
            {group("Antworten", [
              btn(
                "Lückentextfeld",
                <CodeBracketIcon className={iconCls} />,
                () => editor.chain().focus().setLueckentext().run(),
                active.lueckentext,
              ),
              btn(
                "Antwortfeld",
                <CodeBracketSquareIcon className={iconCls} />,
                () => editor.chain().focus().setAnswerBlock().run(),
                active.answerBlock,
              ),
              btn(
                "Aufgabenliste",
                <CheckCircleIcon className={iconCls} />,
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
            {group("Struktur", [
              btn(
                "Seitenumbruch",
                <MinusIcon className={iconCls} />,
                () => editor.chain().focus().setPageBreak().run(),
              ),
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
            ])}
          </div>
        </Tabs.Content>
        <Tabs.Content
          value="tabellen"
          className="exam-editor__tab-content"
        >
          <div className="exam-editor__toolbar-inner">
            {group("Zeilen", [
              btn(
                "Zeile darüber einfügen",
                <ArrowLongUpIcon className={iconCls} />,
                () => editor.chain().focus().addRowBefore().run(),
                false,
                !active.table,
              ),
              btn(
                "Zeile darunter einfügen",
                <ArrowLongDownIcon className={iconCls} />,
                () => editor.chain().focus().addRowAfter().run(),
                false,
                !active.table,
              ),
              btn(
                "Zeile löschen",
                <Bars3Icon className={iconCls} />,
                () => editor.chain().focus().deleteRow().run(),
                false,
                !active.table,
              ),
            ])}
            {group("Spalten", [
              btn(
                "Spalte davor einfügen",
                <ArrowLongLeftIcon className={iconCls} />,
                () => editor.chain().focus().addColumnBefore().run(),
                false,
                !active.table,
              ),
              btn(
                "Spalte danach einfügen",
                <ArrowLongRightIcon className={iconCls} />,
                () => editor.chain().focus().addColumnAfter().run(),
                false,
                !active.table,
              ),
              btn(
                "Spalte löschen",
                <ViewColumnsIcon className={iconCls} />,
                () => editor.chain().focus().deleteColumn().run(),
                false,
                !active.table,
              ),
            ])}
            {group("Tabelle", [
              btn(
                "Kopfzeile umschalten",
                <TableCellsIcon className={iconCls} />,
                () => editor.chain().focus().toggleHeaderRow().run(),
                false,
                !active.table,
              ),
              btn(
                "Tabelle löschen",
                <TrashIcon className={iconCls} />,
                () => editor.chain().focus().deleteTable().run(),
                false,
                !active.table,
              ),
            ])}
          </div>
        </Tabs.Content>
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
        "exam-editor__status" +
        (isError ? " exam-editor__status--error" : "")
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
