import { createReactHook } from "./create_react_hook";

export const ExamCorrectionEditor = createReactHook({
  name: "ExamCorrectionEditor",
  mapProps: (hook, { dataset, initialContent, api }) => {
    // Container ref lets the LiveView dispatch DOM events into the editor.
    hook._containerRef = { current: hook.el };

    return {
      initialContent,
      save: (doc, opts) =>
        api.saveExamCorrectionPart(
          dataset.examId,
          dataset.submissionId,
          dataset.partId,
          doc?.content ?? [],
          opts,
        ),
      mode: "correction",
      containerRef: hook._containerRef,
    };
  },
  // Server-pushed content reload (e.g. after AI correction) is relayed as a
  // custom DOM event the Tiptap editor listens for.
  afterRender: (hook) => {
    hook.handleEvent("reload-content", ({ content: json }) => {
      let newContent = {};
      try {
        newContent = json ? JSON.parse(json) : {};
      } catch (err) {
        console.error("ExamCorrectionEditor: invalid reload content JSON", err);
      }
      hook.el.dispatchEvent(
        new CustomEvent("tiptap:setContent", { detail: newContent }),
      );
    });
  },
});
