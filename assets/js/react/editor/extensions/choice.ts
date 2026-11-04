// Single choice: radio options grouped per question, their ids and keys.

import { Node, Extension, type Editor } from "@tiptap/core";
import { NodeSelection, Plugin, PluginKey, TextSelection, type EditorState, type Transaction } from "prosemirror-state";
import type { Node as PMNode, NodeType } from "@tiptap/pm/model";
import { Decoration, DecorationSet } from "@tiptap/pm/view";
import { generateAnswerId, generateOptionId } from "../ids";
import { verdictAttribute } from "./answers";
import { findAncestorDepth } from "./guards";

// --- Single Choice (`choice`) ---------------------------------------------
//
// A radio is an inline atom that can sit anywhere — a table cell, a paragraph,
// a list item. The group is not the nesting but the `groupId` attribute: all
// radios with the same `groupId` are ONE question (one verdict, one points
// share, one model answer). That is what lets a table row "( ) analog |
// ( ) digital" be a group although its options live in different cells. The
// server side of the same rules: `Tasky.Correction.Choice`.
//
// Grouping is proposed, not imposed: a new radio joins the group of its table
// row, of its own paragraph, or of the block right before it; the teacher can
// split it off or join it to the previous group from the toolbar.

type ChoiceOptions = {
  /** Clicking a radio chooses it (sample solution). */
  interactive: boolean;
  /** Authoring aids: group highlight, Enter adds a radio of the same group. */
  authoring: boolean;
};

// Chooses the radio at `pos`, or clears it when it is already chosen, and
// clears every other radio of its group — one transaction, so "at most one
// per group" holds in every saved state.
function toggleChoice(tr: Transaction, pos: number): Transaction {
  const target = tr.doc.nodeAt(pos);
  if (!target || target.type.name !== "choice") return tr;

  const groupId = target.attrs.groupId;
  const checked = !target.attrs.checked;

  tr.doc.descendants((node, p) => {
    if (node.type.name !== "choice" || node.attrs.groupId !== groupId) return;
    const next = p === pos ? checked : false;
    if (node.attrs.checked !== next) {
      tr.setNodeMarkup(p, undefined, { ...node.attrs, checked: next });
    }
  });

  return tr;
}

function findChoiceIn(node: PMNode, last = false): PMNode | null {
  const found: PMNode[] = [];
  node.descendants((child) => {
    if (found.length > 0 && !last) return false;
    if (child.type.name === "choice") found.push(child);
    return true;
  });
  return (last ? found[found.length - 1] : found[0]) ?? null;
}

// The group a radio inserted at the cursor joins by default (see above), or
// null for a new group. Inside a table it never looks beyond its own row.
function defaultChoiceGroup(state: EditorState): string | null {
  const { $from } = state.selection;

  const rowDepth = findAncestorDepth($from, "tableRow");
  if (rowDepth !== null) {
    return findChoiceIn($from.node(rowDepth))?.attrs.groupId ?? null;
  }

  const own = findChoiceIn($from.parent);
  if (own) return own.attrs.groupId;

  // The closest previous sibling block: the "( ) Bern" line above.
  for (let d = $from.depth; d > 0; d--) {
    const index = $from.index(d - 1);
    if (index === 0) continue;
    const prev = $from.node(d - 1).child(index - 1);
    if (prev.type.name === "heading" && prev.attrs.level === 3) return null;
    if (prev.type.name === "table") return null;
    return findChoiceIn(prev, true)?.attrs.groupId ?? null;
  }

  return null;
}

type ChoiceLine = { pos: number; node: PMNode; key: number };

// The lines a Single-Choice click acts on: the non-empty paragraphs the
// selection touches, or the cursor's own line — never a Multiple-Choice item,
// which is an answer of its own. `key` is the table row a line sits in (-1
// outside a table), since a row is one question there.
function choiceLinesOf(state: EditorState): ChoiceLine[] {
  const lines: ChoiceLine[] = [];

  const add = (node: PMNode, pos: number) => {
    if (node.type.name !== "paragraph" || node.childCount === 0) return;
    if (lines.some((l) => l.pos === pos)) return;
    const $pos = state.doc.resolve(pos);
    if (findAncestorDepth($pos, "taskItem") !== null) return;
    const rowDepth = findAncestorDepth($pos, "tableRow");
    lines.push({ pos, node, key: rowDepth === null ? -1 : $pos.before(rowDepth) });
  };

  if (state.selection.empty) {
    const { $from } = state.selection;
    if ($from.depth > 0) add($from.parent, $from.before());
  } else {
    for (const range of state.selection.ranges) {
      state.doc.nodesBetween(range.$from.pos, range.$to.pos, (node, pos) => {
        if (node.type.name !== "paragraph") return true;
        add(node, pos);
        return false;
      });
    }
  }

  return lines;
}

/**
 * Whether the Single-Choice button shows as active: a radio is selected, or
 * every line it would act on already has one — clicking then removes them.
 */
export function isSingleChoiceActive(state: EditorState): boolean {
  if (selectedChoice(state)) return true;
  const lines = choiceLinesOf(state);
  return lines.length > 0 && lines.every((l) => findChoiceIn(l.node) !== null);
}

// Puts a radio at the start of every line that has none. Lines of one table
// row, or all lines outside a table, form one question: they join a group one
// of them already has, the group the cursor's line would join (see
// `defaultChoiceGroup`), or else a new one.
function addChoices(
  state: EditorState,
  tr: Transaction,
  lines: ChoiceLine[],
  type: NodeType,
) {
  const groups = new Map<number, string>();
  for (const { node, key } of lines) {
    const existing = findChoiceIn(node);
    if (existing && !groups.has(key)) groups.set(key, existing.attrs.groupId);
  }

  // Back to front, so the positions still to come stay valid.
  for (const { pos, node, key } of [...lines].sort((a, b) => b.pos - a.pos)) {
    if (findChoiceIn(node)) continue;
    if (!groups.has(key)) {
      const near = state.selection.empty ? defaultChoiceGroup(state) : null;
      groups.set(key, near ?? generateAnswerId());
    }
    tr.insert(
      pos + 1,
      type.create({
        groupId: groups.get(key),
        optionId: generateOptionId(),
        checked: false,
      }),
    );
  }
}

// Takes every radio out of `lines`.
function removeChoices(tr: Transaction, lines: ChoiceLine[]) {
  const positions: { from: number; to: number }[] = [];
  for (const { pos, node } of lines) {
    node.forEach((child, offset) => {
      if (child.type.name !== "choice") return;
      const from = pos + 1 + offset;
      positions.push({ from, to: from + child.nodeSize });
    });
  }
  for (const { from, to } of positions.sort((a, b) => b.from - a.from)) {
    tr.delete(from, to);
  }
}

function selectedChoice(state: EditorState): { node: PMNode; pos: number } | null {
  const { selection } = state;
  if (selection instanceof NodeSelection && selection.node.type.name === "choice") {
    return { node: selection.node, pos: selection.from };
  }
  return null;
}

const choiceGroupHighlightKey = new PluginKey("choiceGroupHighlight");

export const Choice = Node.create<ChoiceOptions>({
  name: "choice",
  group: "inline",
  inline: true,
  atom: true,
  selectable: true,
  draggable: false,

  addOptions() {
    return { interactive: false, authoring: false };
  },

  addAttributes() {
    return {
      groupId: {
        default: null,
        parseHTML: (el: HTMLElement) => el.getAttribute("data-group-id"),
        renderHTML: (attrs: Record<string, unknown>) =>
          attrs.groupId != null ? { "data-group-id": attrs.groupId } : {},
      },
      optionId: {
        default: null,
        parseHTML: (el: HTMLElement) => el.getAttribute("data-option-id"),
        renderHTML: (attrs: Record<string, unknown>) =>
          attrs.optionId != null ? { "data-option-id": attrs.optionId } : {},
      },
      checked: {
        default: false,
        parseHTML: (el: HTMLElement) => el.getAttribute("data-checked") === "true",
        renderHTML: (attrs: Record<string, unknown>) => ({
          "data-checked": attrs.checked ? "true" : "false",
        }),
      },
      ...verdictAttribute,
      // Set only by `Tasky.Correction.SolutionHints`: the right radio, shown
      // in the review when the group was not answered right.
      correct: {
        default: null,
        parseHTML: (el: HTMLElement) =>
          el.getAttribute("data-correct") === "true" ? true : null,
        renderHTML: (attrs: Record<string, unknown>) =>
          attrs.correct ? { "data-correct": "true" } : {},
      },
    };
  },

  parseHTML() {
    return [{ tag: "span.choice-radio" }];
  },

  renderHTML({ HTMLAttributes }) {
    return ["span", { ...HTMLAttributes, class: "choice-radio" }];
  },

  addNodeView() {
    const { interactive } = this.options;

    return ({ node, getPos, editor }) => {
      const dom = document.createElement("span");
      dom.className = "choice-radio";
      dom.contentEditable = "false";
      dom.setAttribute("role", "radio");

      // `data-choice-verdict`, not `data-verdict`: the generic verdict rules
      // would hang a ✅ on every radio of the group.
      const paint = (n: PMNode) => {
        dom.setAttribute("aria-checked", n.attrs.checked ? "true" : "false");
        dom.dataset.checked = n.attrs.checked ? "true" : "false";
        dom.dataset.groupId = n.attrs.groupId ?? "";
        if (n.attrs.verdict) dom.dataset.choiceVerdict = n.attrs.verdict;
        else delete dom.dataset.choiceVerdict;
        if (n.attrs.correct) dom.dataset.correct = "true";
        else delete dom.dataset.correct;
      };
      paint(node);

      if (interactive) {
        dom.classList.add("is-interactive");
        dom.addEventListener("mousedown", (event) => {
          if (!editor.isEditable || typeof getPos !== "function") return;
          event.preventDefault();
          const pos = getPos();
          if (typeof pos !== "number") return;
          editor.view.dispatch(toggleChoice(editor.state.tr, pos));
        });
      }

      return {
        dom,
        update: (updated: PMNode) => {
          if (updated.type.name !== "choice") return false;
          paint(updated);
          return true;
        },
        stopEvent: (event: Event) => interactive && event.type === "mousedown",
        ignoreMutation: () => true,
      };
    };
  },

  addCommands() {
    return {
      // Toggles Single-Choice like Multiple-Choice toggles its checkboxes:
      // lines without a radio get one at their start, and when every line
      // already has one, they lose it again. A selected radio is removed. On
      // an empty line the radio goes in at the cursor.
      toggleSingleChoice:
        () =>
        ({ state, tr, chain, dispatch }: any) => {
          const sel = selectedChoice(state);
          if (sel) {
            if (dispatch) dispatch(tr.delete(sel.pos, sel.pos + sel.node.nodeSize));
            return true;
          }

          const lines = choiceLinesOf(state);
          if (lines.length === 0) {
            const groupId = defaultChoiceGroup(state) ?? generateAnswerId();
            return chain()
              .insertContent({
                type: this.name,
                attrs: { groupId, optionId: generateOptionId(), checked: false },
              })
              .run();
          }

          if (dispatch) {
            if (isSingleChoiceActive(state)) removeChoices(tr, lines);
            else addChoices(state, tr, lines, this.type);
            dispatch(tr.scrollIntoView());
          }
          return true;
        },

      // The selected radio leaves its group and starts a new one.
      choiceNewGroup:
        () =>
        ({ state, tr, dispatch }: any) => {
          const sel = selectedChoice(state);
          if (!sel) return false;
          if (dispatch) {
            tr.setNodeMarkup(sel.pos, undefined, {
              ...sel.node.attrs,
              groupId: generateAnswerId(),
              checked: false,
            });
            tr.setSelection(NodeSelection.create(tr.doc, sel.pos));
            dispatch(tr);
          }
          return true;
        },

      // The selected radio joins the group of the closest radio before it
      // with a different group — never across a question heading, since a
      // group must stay inside one question.
      choiceJoinPrevious:
        () =>
        ({ state, tr, dispatch }: any) => {
          const sel = selectedChoice(state);
          if (!sel) return false;

          let target: string | null = null;
          state.doc.nodesBetween(0, sel.pos, (node: PMNode) => {
            if (node.type.name === "heading" && node.attrs.level === 3) {
              target = null;
            } else if (
              node.type.name === "choice" &&
              node.attrs.groupId !== sel.node.attrs.groupId
            ) {
              target = node.attrs.groupId;
            }
            return true;
          });
          if (target === null) return false;

          if (dispatch) {
            tr.setNodeMarkup(sel.pos, undefined, {
              ...sel.node.attrs,
              groupId: target,
              checked: false,
            });
            tr.setSelection(NodeSelection.create(tr.doc, sel.pos));
            dispatch(tr);
          }
          return true;
        },
    } as any;
  },

  addKeyboardShortcuts() {
    const shortcuts: Record<string, (props: { editor: Editor }) => boolean> = {};

    if (this.options.interactive) {
      // Space on a selected radio chooses it, as on a native radio.
      shortcuts.Space = ({ editor }) => {
        const sel = selectedChoice(editor.state);
        if (!sel) return false;
        editor.view.dispatch(toggleChoice(editor.state.tr, sel.pos));
        return true;
      };
    }

    if (this.options.authoring) {
      shortcuts.Enter = ({ editor }) => continueChoiceLine(editor);
    }

    return shortcuts;
  },

  addProseMirrorPlugins() {
    if (!this.options.authoring) return [];

    // Which radios belong together is invisible in the text; while a radio is
    // selected, its whole group is outlined.
    return [
      new Plugin({
        key: choiceGroupHighlightKey,
        props: {
          decorations(state) {
            const sel = selectedChoice(state);
            if (!sel) return null;
            const decorations: Decoration[] = [];
            state.doc.descendants((node, pos) => {
              if (
                node.type.name === "choice" &&
                node.attrs.groupId === sel.node.attrs.groupId
              ) {
                decorations.push(
                  Decoration.node(pos, pos + node.nodeSize, {
                    class: "is-group-mate",
                  }),
                );
              }
            });
            return DecorationSet.create(state.doc, decorations);
          },
        },
      }),
    ];
  },
});

// Enter at the end of a line that starts with a radio ("( ) Bern") starts the
// next line with a radio of the same group — the list variant of a single
// choice. On a line that holds nothing but the radio, Enter removes it: the
// list is done.
function continueChoiceLine(editor: Editor): boolean {
  return editor.commands.command(({ tr, state, dispatch }) => {
    const { $from, empty } = state.selection;
    if (!empty) return false;

    const line = $from.parent;
    const first = line.firstChild;
    if (line.type.name !== "paragraph" || !first || first.type.name !== "choice") {
      return false;
    }
    if ($from.parentOffset !== line.content.size) return false;

    if (line.childCount === 1) {
      if (dispatch) dispatch(tr.delete($from.start(), $from.end()));
      return true;
    }

    // In a list the item splits too, so the new line is a new item.
    const wrapper = $from.depth > 1 ? $from.node($from.depth - 1) : null;
    const depth = wrapper && wrapper.type.name === "listItem" ? 2 : 1;

    if (dispatch) {
      tr.split($from.pos, depth);
      const at = $from.pos + 2 * depth;
      tr.insert(
        at,
        state.schema.nodes.choice.create({
          groupId: first.attrs.groupId,
          optionId: generateOptionId(),
          checked: false,
        }),
      );
      tr.setSelection(TextSelection.create(tr.doc, at + 1));
      tr.scrollIntoView();
      dispatch(tr);
    }
    return true;
  });
}

// Gives every radio a group and an option id, and keeps option ids unique
// within a group (a copied radio). Like PartIdStamper, only in editors that
// may change the document's structure.
export const ChoiceIdStamper = Extension.create({
  name: "choiceIdStamper",

  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: new PluginKey("choiceIdStamper"),
        appendTransaction(transactions, _oldState, newState) {
          if (!transactions.some((tr) => tr.docChanged)) return null;

          let tr: Transaction | null = null;
          const seen = new Set<string>();

          newState.doc.descendants((node, pos) => {
            if (node.type.name !== "choice") return;

            const groupId = node.attrs.groupId ?? generateAnswerId();
            let optionId = node.attrs.optionId;
            if (!optionId || seen.has(`${groupId}|${optionId}`)) {
              optionId = generateOptionId();
            }
            seen.add(`${groupId}|${optionId}`);

            if (groupId !== node.attrs.groupId || optionId !== node.attrs.optionId) {
              tr = tr || newState.tr;
              tr.setNodeMarkup(pos, undefined, { ...node.attrs, groupId, optionId });
            }
          });

          return tr;
        },
      }),
    ];
  },
});
