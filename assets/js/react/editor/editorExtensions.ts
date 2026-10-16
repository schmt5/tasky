// The extension list of the exam editor for a given set of mode flags, and
// the check that the stored document can be read with it. Both live here so
// the editor and the tests (editorExtensions.test.js) share one list.

import { getSchema, type AnyExtension } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
import { TaskList } from "@tiptap/extension-list/task-list";
import { TableKit } from "@tiptap/extension-table";
import { Highlight } from "@tiptap/extension-highlight";
import { TextStyle, Color } from "@tiptap/extension-text-style";
import { Placeholder } from "@tiptap/extensions";
import Image from "@tiptap/extension-image";
import {
  HeadingWithPartId,
  PartIdStamper,
  Lueckentext,
  AnswerBlock,
  SolutionHint,
  Callout,
  TaskItemWithId,
  Choice,
  ChoiceIdStamper,
  TeacherComment,
  PreventNodeDeletion,
  LockExamContent,
  PaperAnswerLines,
} from "./extensions";

export interface EditorExtensionFlags {
  editable?: boolean;
  correctionMode?: boolean;
  lockContent?: boolean;
  protectAnswers?: boolean;
  paperMode?: boolean;
  placeholder?: string;
  onLockBlocked?: () => void;
}

export function buildEditorExtensions({
  editable = true,
  correctionMode = false,
  lockContent = false,
  protectAnswers = false,
  paperMode = false,
  placeholder = "",
  onLockBlocked,
}: EditorExtensionFlags = {}): AnyExtension[] {
  return [
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
    SolutionHint,
    Callout,
    TaskList,
    TaskItemWithId.configure({ nested: true }),
    // Choosing a radio is answering: only where answers are given (learner,
    // sample solution), never while authoring or correcting. Authoring
    // gets the group aids instead.
    Choice.configure({
      interactive: editable && lockContent && !paperMode,
      authoring: editable && !lockContent && !correctionMode,
    }),
    ...(lockContent ? [] : [ChoiceIdStamper]),
    TableKit.configure({ table: { resizable: true } }),
    Highlight.configure({ multicolor: true }),
    TextStyle,
    Color,
    Image,
    // In every mode, not only while correcting: the corrected document is
    // handed back to the learner, and a mark the schema does not know makes
    // the whole document unreadable. The toolbar button stays correction-only.
    TeacherComment,
    ...(placeholder ? [Placeholder.configure({ placeholder })] : []),
    ...(protectAnswers ? [PreventNodeDeletion] : []),
    // Must come after PreventNodeDeletion so its Backspace binding wins:
    // later extensions take precedence for the same key in Tiptap.
    ...(paperMode ? [PaperAnswerLines] : []),
    ...(lockContent ? [LockExamContent.configure({ onBlocked: onLockBlocked })] : []),
  ];
}

/**
 * Why `content` cannot be read with `extensions`, or `null` when it can.
 *
 * Tiptap does not fail on such a document: it logs a warning and renders an
 * EMPTY one instead — a blank page for a reader, and for a writer an empty
 * editor whose next autosave overwrites the server copy. Only reading is
 * checked (`nodeFromJSON`), not the content expressions (`check()`): those
 * also reject documents Tiptap renders fine, such as an empty `doc`.
 */
export function findUnreadableContent(
  extensions: AnyExtension[],
  content: unknown,
): Error | null {
  if (!content || typeof content !== "object" || Object.keys(content).length === 0) {
    return null;
  }

  try {
    getSchema(extensions).nodeFromJSON(content);
    return null;
  } catch (error) {
    return error instanceof Error ? error : new Error(String(error));
  }
}
