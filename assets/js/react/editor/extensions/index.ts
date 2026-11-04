// All Tiptap/ProseMirror extensions of the exam editor: the answer-bearing
// nodes, stable-id plumbing, deletion guards, participant content locking and
// the clipboard transforms. Pure editor machinery — no React in here. One
// module per concern; this index is the only import path for the rest of
// the editor.

import type { CalloutColor } from "../constants";

declare module "@tiptap/core" {
  interface Commands<ReturnType> {
    lueckentext: { setLueckentext: () => ReturnType };
    answerBlock: { setAnswerBlock: (options?: { rich?: boolean }) => ReturnType };
    teacherComment: { toggleTeacherComment: () => ReturnType };
    choice: {
      toggleSingleChoice: () => ReturnType;
      choiceNewGroup: () => ReturnType;
      choiceJoinPrevious: () => ReturnType;
    };
    imagePin: {
      insertImagePin: (options: { src: string; aspect: number; alt?: string }) => ReturnType;
    };
    callout: {
      setCallout: (color: CalloutColor) => ReturnType;
      unsetCallout: () => ReturnType;
    };
  }
}

export { HeadingWithPartId, PartIdStamper, Lueckentext, AnswerBlock, TaskItemWithId } from "./answers";
export { Callout } from "./callout";
export { BlockquoteGuarded } from "./blockquote";
export { isSingleChoiceActive, Choice, ChoiceIdStamper } from "./choice";
export { SolutionHint, TeacherComment } from "./annotations";
export { ImagePin, measureAspect, type ImagePinMode } from "./imagePin";
export { PreventNodeDeletion } from "./guards";
export { PaperAnswerLines } from "./paper";
export { unwrapAnswerSlice, withFreshAnswerIds, LockExamContent } from "./lock";
