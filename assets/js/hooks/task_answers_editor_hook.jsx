import { createReactHook, flushAndReport } from "./create_react_hook";

// Student editor for a learning unit (task): mirrors ExamSubmissionEditor
// incl. the flush-before-submit handshake of the "mark as complete" modal.
export const TaskAnswersEditor = createReactHook({
  name: "TaskAnswersEditor",
  setup: (hook) => {
    hook.editorApi = { current: null };
    hook.handleEvent("flush-before-submit", () => flushAndReport(hook));
  },
  mapProps: (hook, { dataset, initialContent, api }) => ({
    initialContent,
    save: (doc, opts) => api.saveTaskAnswers(dataset.taskId, doc, opts),
    mode: "student",
    editable: dataset.editable !== "false",
    apiRef: hook.editorApi,
  }),
});
