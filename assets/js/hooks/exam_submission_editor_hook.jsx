import { createReactHook, flushAndReport } from "./create_react_hook";

// Guest exam editor: the teacher's content is locked, only answer fields
// accept input. Autosaves via the token-gated guest endpoint and answers the
// flush-before-submit handshake of the submit modal.
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
    mode: "student",
    apiRef: hook.editorApi,
  }),
});
