import { createReactHook } from "./create_react_hook";

export const ExamContentEditor = createReactHook({
  name: "ExamContentEditor",
  mapProps: (_hook, { dataset, initialContent, api }) => ({
    initialContent,
    save: (doc, opts) => api.saveExamContent(dataset.examId, doc, opts),
    uploadImage: (file) => api.uploadExamImage(dataset.examId, file),
    // "author" for a question/answer exam, "freeDocument" for an essay one —
    // the server knows the exam's answer_mode, the hook does not.
    mode: dataset.editorMode || "author",
    placeholder:
      dataset.editorMode === "freeDocument"
        ? "Beginne mit der Aufgabenstellung …"
        : "Beginne mit einer Überschrift …",
  }),
});
