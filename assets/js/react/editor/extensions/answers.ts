// Question headings with stable part ids, and the answer-bearing nodes
// (gap, answer block, checklist item) with their stable answer ids.

import { Node, Extension } from "@tiptap/core";
import { Heading } from "@tiptap/extension-heading";
import { TaskItem } from "@tiptap/extension-list/task-item";
import { Plugin, PluginKey } from "prosemirror-state";
import { generateAnswerId, generatePartId } from "../ids";

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
      // Erreichte Punkte der Frage in einer zurückgegebenen Prüfung ("2/4",
      // `Tasky.Exams.learner_part_points/2`); das Stylesheet zeigt sie unter
      // der Frage.
      points: {
        default: null,
        parseHTML: (el: HTMLElement) => el.getAttribute("data-points"),
        renderHTML: (attrs: Record<string, unknown>) =>
          attrs.points != null ? { "data-points": attrs.points } : {},
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
export const verdictAttribute = {
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

export const TaskItemWithId = TaskItem.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      ...answerIdAttribute,
      ...verdictAttribute,
    };
  },
});
