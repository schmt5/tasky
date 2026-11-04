// The blockquote ("Zitat"), guarded like the callout.

import { wrappingInputRule } from "@tiptap/core";
import { Blockquote, inputRegex as blockquoteInputRegex } from "@tiptap/extension-blockquote";
import { liftWholeAncestor, selectionContainsQuestionHeading } from "./callout";
import { findAncestorDepth } from "./guards";

// --- Blockquote ("Zitat") --------------------------------------------------

// Tiptap's Blockquote with the question-heading guard of the callout on every
// way in — button, Mod-Shift-b and the "> " input rule — and the callout's
// whole-box unwrap. Same node name, so stored documents read unchanged.
export const BlockquoteGuarded = Blockquote.extend({
  addCommands() {
    const wrap =
      () =>
      ({ state, commands }: any) =>
        !selectionContainsQuestionHeading(state) && commands.wrapIn(this.name);
    const unwrap =
      () =>
      ({ state, tr, dispatch }: any) =>
        liftWholeAncestor(state, tr, dispatch, this.name);

    return {
      setBlockquote: wrap,
      unsetBlockquote: unwrap,
      toggleBlockquote:
        () =>
        (props: any) =>
          findAncestorDepth(props.state.selection.$from, this.name) === null
            ? wrap()(props)
            : unwrap()(props),
    } as any;
  },

  // Always claims the key: a vetoed toggle would otherwise fall through to
  // Bold's `Mod-B` (Shift makes the key a capital B).
  addKeyboardShortcuts() {
    return {
      "Mod-Shift-b": () => {
        this.editor.commands.toggleBlockquote();
        return true;
      },
    };
  },

  addInputRules() {
    const rule = wrappingInputRule({ find: blockquoteInputRegex, type: this.type });
    const wrapTextblock = rule.handler;
    rule.handler = (props) => {
      const parent = props.state.doc.resolve(props.range.from).parent;
      if (parent.type.name === "heading" && parent.attrs.level === 3) return null;
      return wrapTextblock(props);
    };
    return [rule];
  },
});
