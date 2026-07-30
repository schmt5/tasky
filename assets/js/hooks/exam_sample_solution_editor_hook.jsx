import { createReactHook } from "./create_react_hook";

// One editor per exam part, stacked in the Musterlösung view. Editors are
// lazy-mounted so exams with many parts stay fast: the React/Tiptap instance
// is only created once the part scrolls near the viewport (mount-once).
export const ExamSampleSolutionPartEditor = createReactHook({
  name: "ExamSampleSolutionPartEditor",
  lazy: true,
  minHeight: "320px",
  mapProps: (_hook, { dataset, initialContent, api }) => ({
    initialContent,
    save: (doc, opts) =>
      api.saveExamSampleSolutionPart(
        dataset.examId,
        dataset.partId,
        doc?.content ?? [],
        opts,
      ),
    mode: "solution",
    partId: dataset.partId,
  }),
});
