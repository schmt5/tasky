// The one React/Tiptap editor behind every exam surface. The heavy lifting
// lives in ./editor/*: extensions (answer nodes, guards, clipboard, ids),
// the autosave engine, the toolbar and the icons — this file only composes
// them for the mode at hand (see EDITOR_MODES in ./editor/modes).

import { useCallback, useEffect, useRef, useState } from "react";
import { useEditor, EditorContent } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import { TaskList } from "@tiptap/extension-list/task-list";
import { TableKit } from "@tiptap/extension-table";
import { Highlight } from "@tiptap/extension-highlight";
import { TextStyle, Color } from "@tiptap/extension-text-style";
import { Placeholder } from "@tiptap/extensions";
import Image from "@tiptap/extension-image";
import * as solutionEditorStore from "./solutionEditorStore";
import {
  HeadingWithPartId,
  PartIdStamper,
  Lueckentext,
  AnswerBlock,
  Callout,
  TaskItemWithId,
  TeacherComment,
  PreventNodeDeletion,
  LockExamContent,
  unwrapAnswerSlice,
  withFreshAnswerIds,
} from "./editor/extensions";
import { Toolbar } from "./editor/Toolbar";
import { useAutosave } from "./editor/useAutosave";
import { EDITOR_MODES } from "./editor/modes";

function isEmptyDoc(doc) {
  return !doc || Object.keys(doc).length === 0;
}

export default function ExamContentEditor({
  initialContent,
  save,
  mode = null,
  hideAnswers = false,
  lockContent = false,
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
  lockHintText = null,
}) {
  // Mode presets bundle the prop matrix. NOTE: the preset WINS over an
  // explicit prop — `preset.x ?? x` only falls back to the prop when the
  // preset leaves the flag undefined. To vary a flag, add a preset; do not
  // try to override one from the call site.
  const preset = (mode && EDITOR_MODES[mode]) || {};
  hideAnswers = preset.hideAnswers ?? hideAnswers;
  lockContent = preset.lockContent ?? lockContent;
  correctionMode = preset.correctionMode ?? correctionMode;
  notFullWidth = preset.notFullWidth ?? notFullWidth;
  hideQuestion = preset.hideQuestion ?? hideQuestion;
  editable = preset.editable ?? editable;
  solutionMode = preset.solutionMode ?? solutionMode;
  externalToolbar = preset.externalToolbar ?? externalToolbar;

  // Blocked-edit hint (lockContent mode): briefly explains why typing into
  // the exam text has no effect, and pulses the answer fields.
  const [lockHintVisible, setLockHintVisible] = useState(false);
  const lockHintTimerRef = useRef(null);
  const rootRef = useRef(null);

  const { status, errorMsg, scheduleSave } = useAutosave(save, apiRef);

  // Stable identity: useEditor builds the extension list once, so this must
  // not change across renders.
  const showLockHint = useCallback(() => {
    setLockHintVisible(true);
    if (lockHintTimerRef.current) clearTimeout(lockHintTimerRef.current);
    lockHintTimerRef.current = setTimeout(() => {
      lockHintTimerRef.current = null;
      setLockHintVisible(false);
    }, 2400);
    // Shared-toolbar mode: the pill lives in the toolbar's React root, so the
    // flash is relayed through the store. The local state above still drives
    // the answer-field pulse on this part editor.
    if (externalToolbar) solutionEditorStore.flashLockHint();
  }, [externalToolbar]);

  useEffect(
    () => () => {
      if (lockHintTimerRef.current) clearTimeout(lockHintTimerRef.current);
    },
    [],
  );

  const editor = useEditor({
    extensions: [
      // StarterKit bringt die Link-Extension mit (autolink, linkOnPaste,
      // target="_blank" + rel="noopener noreferrer nofollow" sind Defaults);
      // nur das Default-Protokoll wäre http, ein gepastetes "www.foo.ch" also
      // unverschlüsselt.
      StarterKit.configure({
        horizontalRule: false,
        heading: false,
        link: { defaultProtocol: "https" },
      }),
      HeadingWithPartId,
      ...(lockContent ? [] : [PartIdStamper]),
      Lueckentext,
      AnswerBlock,
      Callout,
      TaskList,
      TaskItemWithId.configure({ nested: true }),
      TableKit.configure({ table: { resizable: true } }),
      Highlight.configure({ multicolor: true }),
      TextStyle,
      Color,
      Image,
      ...(placeholder ? [Placeholder.configure({ placeholder })] : []),
      ...(hideAnswers ? [PreventNodeDeletion] : []),
      ...(lockContent
        ? [LockExamContent.configure({ onBlocked: showLockHint })]
        : []),
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
        spellcheck: "false",
      },
      transformCopied: unwrapAnswerSlice,
      // Safety net for clipboard content produced before transformCopied
      // existed or by other views (open depths survive via data-pm-slice).
      transformPasted: (slice, view) =>
        withFreshAnswerIds(unwrapAnswerSlice(slice), view),
    },
  });

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
        (solutionMode ? " exam-editor--solution-mode" : "") +
        (lockHintVisible ? " exam-editor--lock-flash" : "")
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
          lockHintVisible={lockContent && lockHintVisible}
          lockHintEnabled={lockContent}
          lockHintText={lockHintText || undefined}
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

export { Toolbar };
