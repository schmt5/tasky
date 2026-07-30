import { createReactHook } from "./create_react_hook";

export const ExamContentEditor = createReactHook({
  name: "ExamContentEditor",
  mapProps: (_hook, { dataset, initialContent, api }) => ({
    initialContent,
    save: (doc, opts) => api.saveExamContent(dataset.examId, doc, opts),
    uploadImage: (file) => api.uploadExamImage(dataset.examId, file),
    placeholder: "Beginne mit einer Überschrift …",
  }),
});
