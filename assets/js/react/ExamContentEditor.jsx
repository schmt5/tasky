import { Children, useCallback, useEffect, useRef, useState } from "react";
import { useEditor, EditorContent, useEditorState } from "@tiptap/react";
import { Node } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
import { TaskList } from "@tiptap/extension-list/task-list";
import { TaskItem } from "@tiptap/extension-list/task-item";

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
} from "@heroicons/react/24/outline";
import { saveExamContent } from "./api";

const AUTOSAVE_DELAY_MS = 1000;

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

  const group = (label, children) => (
    <div className="exam-editor__group">
      <div className="exam-editor__group-btns">
        {Children.map(children, (c) => c)}
      </div>
      <span className="exam-editor__group-label">{label}</span>
    </div>
  );

  return (
    <div className="exam-editor__toolbar">
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
        ])}
        <StatusIndicator status={status} errorMsg={errorMsg} />
      </div>
    </div>
  );
}

function StatusIndicator({ status, errorMsg }) {
  const label =
    status === "saving"
      ? "Speichert..."
      : status === "saved"
        ? "Gespeichert"
        : status === "error"
          ? errorMsg || "Fehler beim Speichern"
          : "";
  const mod =
    status === "saving"
      ? " exam-editor__status--saving"
      : status === "error"
        ? " exam-editor__status--error"
        : "";
  return <div className={"exam-editor__status" + mod}>{label}</div>;
}
