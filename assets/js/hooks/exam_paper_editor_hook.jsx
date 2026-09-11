import { createReactHook } from "./create_react_hook";

// The teacher sizing the paper version. Editable, but the "paper" preset locks
// everything except the answer boxes: clicking into one and pressing Enter
// adds a writing line, Backspace removes one.
//
// Saves to /paper-layout, not /content — only the line counts are persisted,
// and the exam document the learners sit is never written from here.
export const ExamPaperEditor = createReactHook({
  name: "ExamPaperEditor",
  mapProps: (_hook, { dataset, initialContent, api }) => ({
    initialContent,
    save: (doc, opts) => api.savePaperLayout(dataset.examId, doc, opts),
    mode: "paper",
  }),
});
