import { useCallback, useEffect, useRef, useState } from "react";
import { useEditor, EditorContent, useEditorState } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
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
    extensions: [StarterKit],
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
        <EditorContent editor={editor} />
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
      blockquote: editor.isActive("blockquote"),
      code: editor.isActive("code"),
      codeBlock: editor.isActive("codeBlock"),
    }),
  });

  const btn = (label, action, isActive = false, disabled = false) => (
    <button
      type="button"
      className={"exam-editor__btn" + (isActive ? " is-active" : "")}
      onMouseDown={(e) => e.preventDefault()}
      onClick={action}
      disabled={disabled}
    >
      {label}
    </button>
  );

  return (
    <div className="exam-editor__toolbar">
      {btn("B", () => editor.chain().focus().toggleBold().run(), active.bold)}
      {btn(
        "I",
        () => editor.chain().focus().toggleItalic().run(),
        active.italic,
      )}
      <span className="exam-editor__sep" />
      {btn(
        "H1",
        () => editor.chain().focus().toggleHeading({ level: 1 }).run(),
        active.h1,
      )}
      {btn(
        "H2",
        () => editor.chain().focus().toggleHeading({ level: 2 }).run(),
        active.h2,
      )}
      {btn(
        "H3",
        () => editor.chain().focus().toggleHeading({ level: 3 }).run(),
        active.h3,
      )}
      <span className="exam-editor__sep" />
      {btn(
        "• Liste",
        () => editor.chain().focus().toggleBulletList().run(),
        active.bulletList,
      )}
      {btn(
        "1. Liste",
        () => editor.chain().focus().toggleOrderedList().run(),
        active.orderedList,
      )}
      {btn(
        "„ Zitat",
        () => editor.chain().focus().toggleBlockquote().run(),
        active.blockquote,
      )}
      <span className="exam-editor__sep" />
      {btn(
        "‹ Code ›",
        () => editor.chain().focus().toggleCode().run(),
        active.code,
      )}
      {btn(
        "Antwortfeld",
        () => editor.chain().focus().toggleCodeBlock().run(),
        active.codeBlock,
      )}
      {btn("—", () => editor.chain().focus().setHorizontalRule().run())}
      <StatusIndicator status={status} errorMsg={errorMsg} />
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
