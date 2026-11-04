// Deletion guards and answer-field navigation.

import { Extension, type Editor } from "@tiptap/core";
import { Plugin, PluginKey } from "prosemirror-state";
import type { Node as PMNode, ResolvedPos } from "@tiptap/pm/model";

// --- Deletion guards & answer-field navigation -----------------------------

function countByType(doc: PMNode, typeName: string): number {
  let n = 0;
  doc.descendants((node) => {
    if (node.type.name === typeName) n++;
  });
  return n;
}

export function findAncestorDepth($pos: ResolvedPos, typeName: string): number | null {
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
    const protectedTypes = ["lueckentext", "answerBlock", "choice"];
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
