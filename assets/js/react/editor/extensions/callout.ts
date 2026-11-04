// The callout ("Hinweisbox") and the guards it shares with the blockquote.

import { Node } from "@tiptap/core";
import { type EditorState, type Transaction } from "prosemirror-state";
import type { Node as PMNode } from "@tiptap/pm/model";
import { liftTarget } from "@tiptap/pm/transform";
import { CALLOUT_COLOR_VALUES, DEFAULT_CALLOUT_COLOR, type CalloutColor } from "../constants";
import { findAncestorDepth } from "./guards";

// --- Callout ("Hinweisbox") ------------------------------------------------

const normalizeCalloutColor = (value: unknown): CalloutColor =>
  (CALLOUT_COLOR_VALUES as readonly string[]).includes(value as string)
    ? (value as CalloutColor)
    : DEFAULT_CALLOUT_COLOR;

// A question heading must never end up inside a callout or a blockquote:
// ExamDoc splits the
// document at TOP-LEVEL h3 only, so a wrapped question would vanish from
// the part list — and Exams.prune_orphan_block_points then drops that part's
// custom block points on the next save.
export function selectionContainsQuestionHeading(state: any): boolean {
  const { from, to } = state.selection;
  let found = false;
  state.doc.nodesBetween(from, to, (node: PMNode) => {
    if (node.type.name === "heading" && node.attrs.level === 3) found = true;
  });
  return found;
}

// Lifts the whole content of the nearest `name` ancestor, not the selection's
// own block range — `commands.lift()` (what Tiptap's Blockquote uses) would
// merely outdent a list item when the cursor sits in a nested list and leave
// the box standing.
export function liftWholeAncestor(
  state: EditorState,
  tr: Transaction,
  dispatch: ((tr: Transaction) => void) | undefined,
  name: string,
): boolean {
  const $from = state.selection.$from;
  const depth = findAncestorDepth($from, name);
  if (depth === null) return false;

  const range = state.doc
    .resolve($from.start(depth))
    .blockRange(state.doc.resolve($from.end(depth)));
  if (!range) return false;

  const target = liftTarget(range);
  if (target == null) return false;
  if (dispatch) dispatch(tr.lift(range, target).scrollIntoView());
  return true;
}

export const Callout = Node.create({
  name: "callout",
  group: "block",
  content: "block+",
  defining: true,

  addAttributes() {
    return {
      color: {
        default: DEFAULT_CALLOUT_COLOR,
        // Total on both ends: a hand-edited or corrupt `data-color` degrades
        // to the default instead of rendering an unstyled box.
        parseHTML: (el: HTMLElement) =>
          normalizeCalloutColor(el.getAttribute("data-color")),
        renderHTML: (attrs: Record<string, unknown>) => ({
          "data-color": normalizeCalloutColor(attrs.color),
        }),
      },
    };
  },

  parseHTML() {
    return [{ tag: "div.callout" }];
  },

  renderHTML({ HTMLAttributes }) {
    return ["div", { ...HTMLAttributes, class: "callout" }, 0];
  },

  addCommands() {
    return {
      // Deliberately not `toggleWrap`: it compares attributes, so picking a
      // different colour inside an existing callout would nest a second box
      // instead of recolouring, and picking the current colour would unwrap.
      setCallout:
        (color: CalloutColor) =>
        ({ state, tr, dispatch, commands }: any) => {
          const next = normalizeCalloutColor(color);
          const depth = findAncestorDepth(state.selection.$from, this.name);

          if (depth !== null) {
            const pos = state.selection.$from.before(depth);
            const node = state.doc.nodeAt(pos);
            if (!node) return false;
            if (node.attrs.color === next) return true;
            if (dispatch) {
              dispatch(
                tr.setNodeMarkup(pos, undefined, { ...node.attrs, color: next }),
              );
            }
            return true;
          }

          if (selectionContainsQuestionHeading(state)) return false;

          return commands.wrapIn(this.name, { color: next });
        },

      unsetCallout:
        () =>
        ({ state, tr, dispatch }: any) =>
          liftWholeAncestor(state, tr, dispatch, this.name),
    } as any;
  },
});
