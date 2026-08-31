import { createReactHook, flushAndReport } from "./create_react_hook";

// Guest exam editor. In an answer-field exam the teacher's content is locked
// and only answer fields accept input; in a free-document exam the learner
// edits the whole document ("freeDocument" preset, pushed down from the
// server as data-editor-mode). Autosaves via the token-gated guest endpoint
// and answers the flush-before-submit handshake of the submit modal.
export const ExamSubmissionEditor = createReactHook({
  name: "ExamSubmissionEditor",
  // Registered before the dynamic imports resolve so an early
  // "flush-before-submit" still gets an answer: no editor → nothing typed →
  // nothing unsaved.
  setup: (hook) => {
    hook.editorApi = { current: null };
    hook.handleEvent("flush-before-submit", () => flushAndReport(hook));
  },
  mapProps: (hook, { dataset, initialContent, api }) => ({
    initialContent,
    save: (doc, opts) =>
      api.saveExamSubmissionContent(dataset.examToken, doc, opts),
    mode: dataset.editorMode || "student",
    apiRef: hook.editorApi,
  }),
});
