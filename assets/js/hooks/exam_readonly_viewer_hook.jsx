import { createReactHook } from "./create_react_hook";

export const ExamReadOnlyViewer = createReactHook({
  name: "ExamReadOnlyViewer",
  mapProps: (_hook, { initialContent }) => ({
    initialContent,
    save: () => Promise.resolve(),
    mode: "readonly",
  }),
});
