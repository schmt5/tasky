// All Tiptap/ProseMirror extensions of the exam editor: the answer-bearing
// nodes, stable-id plumbing, deletion guards, participant content locking and
// the clipboard transforms. Pure editor machinery — no React in here.

import { Node, Mark, Extension, type Editor } from "@tiptap/core";
import { Heading } from "@tiptap/extension-heading";
import { TaskItem } from "@tiptap/extension-list/task-item";
import {
  NodeSelection,
  Plugin,
  PluginKey,
  TextSelection,
  type EditorState,
  type Transaction,
} from "prosemirror-state";
import { Slice, Fragment } from "@tiptap/pm/model";
import type { Node as PMNode, NodeType, ResolvedPos } from "@tiptap/pm/model";
import { liftTarget } from "@tiptap/pm/transform";
import { Decoration, DecorationSet, type EditorView } from "@tiptap/pm/view";

import { generateAnswerId, generateOptionId, generatePartId } from "./ids";
import {
  CALLOUT_COLOR_VALUES,
  DEFAULT_CALLOUT_COLOR,
  type CalloutColor,
} from "./constants";

declare module "@tiptap/core" {
  interface Commands<ReturnType> {
    lueckentext: { setLueckentext: () => ReturnType };
    answerBlock: { setAnswerBlock: () => ReturnType };
    teacherComment: { toggleTeacherComment: () => ReturnType };
    choice: {
      toggleSingleChoice: () => ReturnType;
      choiceNewGroup: () => ReturnType;
      choiceJoinPrevious: () => ReturnType;
    };
    callout: {
      setCallout: (color: CalloutColor) => ReturnType;
      unsetCallout: () => ReturnType;
    };
  }
}

// Question headings (h3) carry a stable partId so all part-keyed data
// (points, AI config, corrected parts) survives reordering and insertion.
export const HeadingWithPartId = Heading.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      partId: {
        default: null,
        parseHTML: (el: HTMLElement) => el.getAttribute("data-part-id"),
        renderHTML: (attrs: Record<string, unknown>) =>
          attrs.partId ? { "data-part-id": attrs.partId } : {},
      },
    };
  },
});

// Stamps a partId onto any level-3 heading that lacks one (typed headings,
// legacy docs). Only active in the content editor — locked editors can't
// create headings and their filterTransaction would veto the stamp.
export const PartIdStamper = Extension.create({
  name: "partIdStamper",

  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: new PluginKey("partIdStamper"),
        appendTransaction(transactions, _oldState, newState) {
          if (!transactions.some((tr) => tr.docChanged)) return null;

          let tr: typeof newState.tr | null = null;
          newState.doc.descendants((node, pos) => {
            if (
              node.type.name === "heading" &&
              node.attrs.level === 3 &&
              !node.attrs.partId
            ) {
              tr = tr || newState.tr;
              tr.setNodeMarkup(pos, undefined, {
                ...node.attrs,
                partId: generatePartId(),
              });
            }
          });

          return tr;
        },
      }),
    ];
  },
});

const answerIdAttribute = {
  answerId: {
    default: null,
    parseHTML: (el: HTMLElement) => el.getAttribute("data-answer-id"),
    renderHTML: (attrs: Record<string, unknown>) =>
      attrs.answerId ? { "data-answer-id": attrs.answerId } : {},
  },
};

// Das Ergebnis der Selbstkontrolle einer Lerneinheit ("correct" | "wrong"),
// gesetzt von `Tasky.Tasks.SelfCheck` und nur im Read-only-Viewer sichtbar.
// Bewusst ein Attribut statt eines ✅/❌ im Text: das Rendern ist Sache des
// Stylesheets, das Dokument bleibt sauber.
//
// In der zurückgegebenen Prüfung kommt die erreichte Punktzahl dazu ("1.5",
// `Tasky.Exams.learner_points/2`); das Stylesheet zeigt dann sie statt 🟡.
const verdictAttribute = {
  verdict: {
    default: null,
    parseHTML: (el: HTMLElement) => el.getAttribute("data-verdict"),
    renderHTML: (attrs: Record<string, unknown>) =>
      attrs.verdict ? { "data-verdict": attrs.verdict } : {},
  },
  points: {
    default: null,
    parseHTML: (el: HTMLElement) => el.getAttribute("data-points"),
    renderHTML: (attrs: Record<string, unknown>) =>
      attrs.points != null ? { "data-points": attrs.points } : {},
  },
};

export const Lueckentext = Node.create({
  name: "lueckentext",
  inline: true,
  group: "inline",
  content: "inline*",

  addAttributes() {
    return { ...answerIdAttribute, ...verdictAttribute };
  },

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
        ({ chain, state }: { chain: any; state: any }) => {
          const { from, to } = state.selection;
          const text = state.doc.textBetween(from, to);
          const attrs = { answerId: generateAnswerId() };
          if (text) {
            return chain()
              .deleteSelection()
              .insertContent({
                type: this.name,
                attrs,
                content: [{ type: "text", text }],
              })
              .run();
          }
          return chain().insertContent({ type: this.name, attrs }).run();
        },
    } as any;
  },
});

export const AnswerBlock = Node.create({
  name: "answerBlock",
  group: "block",
  content: "block+",
  defining: true,

  addAttributes() {
    return { ...answerIdAttribute, ...verdictAttribute };
  },

  parseHTML() {
    return [{ tag: "div.answer-block" }];
  },

  renderHTML({ HTMLAttributes }) {
    // No DOM `tabindex` here: a focusable wrapper steals browser focus on Tab
    // without moving the ProseMirror selection, desyncing the caret. Tab
    // navigation between answer fields is handled in PreventNodeDeletion.
    return ["div", { ...HTMLAttributes, class: "answer-block" }, 0];
  },

  addCommands() {
    return {
      setAnswerBlock:
        () =>
        ({ chain }: { chain: any }) => {
          const answerId = generateAnswerId();
          return chain()
            .insertContent({
              type: this.name,
              attrs: { answerId },
              content: [{ type: "paragraph" }],
            })
            .run();
        },
    } as any;
  },
});

// --- Callout ("Hinweisbox") ------------------------------------------------

const normalizeCalloutColor = (value: unknown): CalloutColor =>
  (CALLOUT_COLOR_VALUES as readonly string[]).includes(value as string)
    ? (value as CalloutColor)
    : DEFAULT_CALLOUT_COLOR;

// A question heading must never end up inside a callout: ExamDoc splits the
// document at TOP-LEVEL h3 only, so a wrapped question would vanish from the
// part list — and Exams.prune_orphan_block_points then drops that part's
// custom block points on the next save.
function selectionContainsQuestionHeading(state: any): boolean {
  const { from, to } = state.selection;
  let found = false;
  state.doc.nodesBetween(from, to, (node: PMNode) => {
    if (node.type.name === "heading" && node.attrs.level === 3) found = true;
  });
  return found;
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

      // Lifts the callout's whole content, not the selection's own block range
      // — `commands.lift()` (what Blockquote uses) would merely outdent a list
      // item when the cursor sits in a nested list and leave the box standing.
      unsetCallout:
        () =>
        ({ state, tr, dispatch }: any) => {
          const $from = state.selection.$from;
          const depth = findAncestorDepth($from, this.name);
          if (depth === null) return false;

          const range = state.doc
            .resolve($from.start(depth))
            .blockRange(state.doc.resolve($from.end(depth)));
          if (!range) return false;

          const target = liftTarget(range);
          if (target == null) return false;
          if (dispatch) dispatch(tr.lift(range, target).scrollIntoView());
          return true;
        },
    } as any;
  },
});

export const TaskItemWithId = TaskItem.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      ...answerIdAttribute,
      ...verdictAttribute,
    };
  },
});

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
  /** Clicking a radio chooses it (student, sample solution). */
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

// Die Musterlösung eines Antwortfelds, in der Vergleichsansicht einer
// Lerneinheit direkt unter der eigenen Antwort. Eingefügt wird der Knoten
// ausschliesslich serverseitig von `Tasky.Tasks.SelfCheck.review_doc/3` —
// darum kein Command und keine Input-Rule: er kann nicht in ein
// Autoren-Dokument geraten.
export const SolutionHint = Node.create({
  name: "solutionHint",
  group: "block",
  content: "block+",

  parseHTML() {
    return [{ tag: "div.solution-hint" }];
  },

  renderHTML({ HTMLAttributes }) {
    return ["div", { ...HTMLAttributes, class: "solution-hint" }, 0];
  },
});

export const TeacherComment = Mark.create({
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
        ({ commands }: { commands: any }) =>
          commands.toggleMark(this.name),
    } as any;
  },
});

// --- Deletion guards & answer-field navigation -----------------------------

function countByType(doc: PMNode, typeName: string): number {
  let n = 0;
  doc.descendants((node) => {
    if (node.type.name === typeName) n++;
  });
  return n;
}

function findAncestorDepth($pos: ResolvedPos, typeName: string): number | null {
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
// Loaded only in `paper` mode; the student and Musterlösung editors keep
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

// --- Participant content locking (skeleton comparison) ---------------------

// Participant mode: everything the teacher authored is read-only; only the
// answer fields accept input. Instead of enumerating every way the exam text
// could be damaged (select-all delete, paste-over, drag-drop, table commands,
// …), compare the document's *skeleton* — its full JSON with answer-field
// contents stripped and checkbox states normalized — before and after each
// transaction, and veto any transaction that changes it.
const ANSWER_CONTENT_TYPES = ["lueckentext", "answerBlock"];

type JsonNode = {
  type?: string;
  attrs?: Record<string, unknown>;
  content?: JsonNode[];
  [key: string]: unknown;
};

function stripAnswers(json: JsonNode): JsonNode {
  if (json.type && ANSWER_CONTENT_TYPES.includes(json.type)) {
    const { content, ...skeleton } = json;
    return skeleton;
  }
  // Choosing a radio is an answer; which radios exist is not.
  if (json.type === "choice") {
    return { ...json, attrs: { ...json.attrs, checked: null } };
  }
  // Ticking a multiple-choice box is an answer; the item's label text is not.
  if (json.type === "taskItem") {
    return {
      ...json,
      attrs: { ...json.attrs, checked: null },
      content: json.content?.map(stripAnswers),
    };
  }
  if (json.content) {
    return { ...json, content: json.content.map(stripAnswers) };
  }
  return json;
}

// A selection made *inside* an answer field yields a slice whose outermost
// node is the open answerBlock/lueckentext wrapper, so pasting it would insert
// a whole new answer field (with a duplicate answerId). Strip those open
// wrappers so only the inner content travels via the clipboard. A fully
// selected answer field copied along with surrounding content appears as a
// *closed* node in the slice and is left untouched, so deliberately
// duplicating one in the content editor still works.
export function unwrapAnswerSlice(slice: Slice): Slice {
  let { content, openStart, openEnd } = slice;
  while (
    content.childCount === 1 &&
    openStart > 0 &&
    openEnd > 0 &&
    content.firstChild &&
    ANSWER_CONTENT_TYPES.includes(content.firstChild.type.name)
  ) {
    content = content.firstChild.content;
    openStart--;
    openEnd--;
  }
  if (content === slice.content) return slice;
  return new Slice(content, openStart, openEnd);
}

// Pasted content must never reuse an answerId that already exists in the
// document (copy-paste of an answer field) or twice within the pasted slice —
// colliding ids silently merge two answers in grading. Ids whose original was
// removed (cut-paste) stay unchanged so stored answers/points keep matching.
export function withFreshAnswerIds(slice: Slice, view: EditorView): Slice {
  const taken = new Set<string>();
  view.state.doc.descendants((node) => {
    if (node.attrs?.answerId != null) taken.add(String(node.attrs.answerId));
    if (node.attrs?.partId != null) taken.add(String(node.attrs.partId));
    if (node.attrs?.groupId != null) taken.add(String(node.attrs.groupId));
  });

  // Radio groups are renamed consistently across the slice: a copied table
  // row becomes a new group, but still one group, not one per radio.
  const groupRenames = new Map<string, string>();

  function mapNode(node: PMNode): PMNode {
    let attrs = node.attrs;
    if (attrs && "answerId" in attrs && attrs.answerId != null) {
      if (taken.has(String(attrs.answerId))) {
        attrs = { ...attrs, answerId: generateAnswerId() };
      }
      taken.add(String(attrs.answerId));
    }
    if (node.type.name === "choice" && attrs.groupId != null) {
      const old = String(attrs.groupId);
      if (!groupRenames.has(old)) {
        groupRenames.set(old, taken.has(old) ? generateAnswerId() : old);
      }
      const renamed = groupRenames.get(old)!;
      if (renamed !== old) attrs = { ...attrs, groupId: renamed };
    }
    // Question headings carry a partId — duplicated part ids would merge two
    // parts' points/config, so pasted copies get fresh ones too.
    if (attrs && "partId" in attrs && attrs.partId != null) {
      if (taken.has(String(attrs.partId))) {
        attrs = { ...attrs, partId: generatePartId() };
      }
      taken.add(String(attrs.partId));
    }
    const content = mapFragment(node.content);
    if (attrs === node.attrs && content === node.content) return node;
    return node.type.create(attrs, content, node.marks);
  }

  function mapFragment(fragment: Fragment): Fragment {
    let changed = false;
    const children: PMNode[] = [];
    fragment.forEach((child) => {
      const mapped = mapNode(child);
      if (mapped !== child) changed = true;
      children.push(mapped);
    });
    return changed ? Fragment.fromArray(children) : fragment;
  }

  const content = mapFragment(slice.content);
  if (content === slice.content) return slice;
  return new Slice(content, slice.openStart, slice.openEnd);
}

// ProseMirror docs are immutable, so the skeleton can be cached per doc node.
// An allowed transaction's new doc becomes the next comparison's old doc, so
// in steady state this is one stringify per keystroke.
const skeletonCache = new WeakMap<PMNode, string>();

function docSkeleton(doc: PMNode): string {
  let skeleton = skeletonCache.get(doc);
  if (skeleton === undefined) {
    skeleton = JSON.stringify(stripAnswers(doc.toJSON() as JsonNode));
    skeletonCache.set(doc, skeleton);
  }
  return skeleton;
}

export const LockExamContent = Extension.create({
  name: "lockExamContent",

  addOptions() {
    return {
      // Called when a transaction is vetoed, so the UI can explain why the
      // edit had no effect instead of leaving the editor feeling broken.
      onBlocked: null as null | (() => void),
    };
  },

  addProseMirrorPlugins() {
    const { onBlocked } = this.options;
    return [
      new Plugin({
        key: new PluginKey("lockExamContent"),
        filterTransaction(tr, state) {
          if (!tr.docChanged) return true;
          if (docSkeleton(tr.doc) === docSkeleton(state.doc)) return true;
          onBlocked?.();
          return false;
        },
      }),
    ];
  },
});
