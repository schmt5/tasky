import { createReactHook } from "./create_react_hook";

// One editor per question (h3), stacked in the Musterlösung view of an exam
// or a learning unit. Editors are lazy-mounted so documents with many
// questions stay fast: the React/Tiptap instance is only created once the
// question scrolls near the viewport (mount-once). The page renders the
// endpoint into `data-save-url`, so the hook does not care whose part it is.
export const SampleSolutionPartEditor = createReactHook({
  name: "SampleSolutionPartEditor",
  lazy: true,
  minHeight: "320px",
  mapProps: (_hook, { dataset, initialContent, api }) => ({
    initialContent,
    save: (doc, opts) =>
      api.saveSampleSolutionPart(dataset.saveUrl, doc?.content ?? [], opts),
    mode: "solution",
    partId: dataset.partId,
  }),
});
