import { createReactHook } from "./create_react_hook";

// Korrektur-Editor einer Lerneinheit: die Lehrperson annotiert das
// Antwortdokument der/des Lernenden (Rot-Text, Kommentar-Mark). Ein Editor
// über das ganze Dokument — Lerneinheiten haben keine Teilaufgaben.
export const TaskCorrectionEditor = createReactHook({
  name: "TaskCorrectionEditor",
  mapProps: (_hook, { dataset, initialContent, api }) => ({
    initialContent,
    save: (doc, opts) =>
      api.saveTaskCorrection(dataset.taskId, dataset.submissionId, doc, opts),
    mode: "taskCorrection",
  }),
});
