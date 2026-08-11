import { createReactHook } from "./create_react_hook";

// Musterlösungs-Editor einer Lerneinheit: ein einziger Editor über das ganze
// Dokument (keine Teilaufgaben wie bei Prüfungen), darum nicht lazy und mit
// eigener Toolbar statt der geteilten aus dem Prüfungs-Tab.
export const TaskSampleSolutionEditor = createReactHook({
  name: "TaskSampleSolutionEditor",
  mapProps: (_hook, { dataset, initialContent, api }) => ({
    initialContent,
    save: (doc, opts) => api.saveTaskSampleSolution(dataset.taskId, doc, opts),
    mode: "taskSolution",
    lockHintText:
      "Der Aufgabentext kann hier nicht bearbeitet werden – erfasse die Musterlösung in den Antwortfeldern.",
  }),
});
