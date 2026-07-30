import { createReactHook } from "./create_react_hook";

export const ExamReadOnlyViewer = createReactHook({
  name: "ExamReadOnlyViewer",
  mapProps: (_hook, { initialContent }) => ({
    initialContent,
    save: () => Promise.resolve(),
    mode: "readonly",
  }),
  // Signal for the print-readiness gate (assets/js/print_ready.js): the
  // double rAF guarantees the rendered content has been committed and
  // painted before Gotenberg is told the page is ready.
  afterRender: (hook) => {
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        hook.el.setAttribute("data-print-rendered", "true");
      });
    });
  },
});
