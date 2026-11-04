// Paper-version line sizing of the answer boxes.

import { Extension, type Editor } from "@tiptap/core";
import { TextSelection } from "prosemirror-state";
import type { ResolvedPos } from "@tiptap/pm/model";

// --- Paper-version line sizing --------------------------------------------

// How the teacher sizes an answer box on the paper version: Enter adds a
// writing line, Backspace on an empty line removes it again.
//
// This needs its own binding because the boxes are made of EMPTY paragraphs.
// Tiptap's default Enter reaches ProseMirror's `liftEmptyBlock` there, which
// lifts the paragraph out of the (defining) answerBlock — that changes the
// document skeleton, so `LockExamContent` vetoes the transaction and the key
// looks dead. Splitting only works once a paragraph holds text, which is
// exactly what a blank sheet never has.
//
// Both commands go through a raw transaction rather than `insertContentAt` /
// `deleteRange`: the node being inserted is an *empty* paragraph, and
// `insertContentAt` normalises that away and reports failure.
//
// Loaded only in `paper` mode; the Musterlösung editors keep
// Tiptap's default Enter, where lifting out of a box is the right behaviour.
export const PaperAnswerLines = Extension.create({
  name: "paperAnswerLines",

  addKeyboardShortcuts() {
    return {
      Enter: ({ editor }) => insertPaperLine(editor),
      Backspace: ({ editor }) => removePaperLine(editor),
    };
  },
});

// Depth of the answerBlock the position sits in, or null when outside one.
function answerBlockDepth($pos: ResolvedPos): number | null {
  for (let d = $pos.depth; d > 0; d--) {
    if ($pos.node(d).type.name === "answerBlock") return d;
  }
  return null;
}

function insertPaperLine(editor: Editor): boolean {
  return editor.commands.command(({ tr, state, dispatch }) => {
    const { $from, empty } = state.selection;

    if (!empty) return false;
    if (answerBlockDepth($from) === null) return false;
    if ($from.parent.type.name !== "paragraph") return false;

    const paragraph = state.schema.nodes.paragraph;
    if (!paragraph) return false;

    // After the paragraph the cursor is in, so pressing Enter mid-box adds the
    // line where the teacher is looking rather than at the end.
    const at = $from.after($from.depth);

    if (dispatch) {
      tr.insert(at, paragraph.create());
      tr.setSelection(TextSelection.create(tr.doc, at + 1));
      tr.scrollIntoView();
    }

    return true;
  });
}

function removePaperLine(editor: Editor): boolean {
  return editor.commands.command(({ tr, state, dispatch }) => {
    const { $from, empty } = state.selection;
    const depth = answerBlockDepth($from);

    if (!empty || depth === null) return false;

    const line = $from.parent;
    const block = $from.node(depth);

    // Only an empty line is removable, only from its start, and never the
    // last one: an answerBlock is `block+` and would become invalid.
    if (line.type.name !== "paragraph" || line.content.size > 0) return false;
    if ($from.parentOffset !== 0 || block.childCount <= 1) return false;

    const from = $from.before($from.depth);
    const to = $from.after($from.depth);

    if (dispatch) {
      tr.delete(from, to);
      tr.setSelection(TextSelection.create(tr.doc, Math.max(from - 1, 1)));
      tr.scrollIntoView();
    }

    return true;
  });
}
