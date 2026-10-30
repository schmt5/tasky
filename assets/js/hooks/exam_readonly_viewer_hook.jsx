import { createReactHook } from "./create_react_hook";

export const ExamReadOnlyViewer = createReactHook({
  name: "ExamReadOnlyViewer",
  mapProps: (_hook, { initialContent }) => ({
    initialContent,
    save: () => Promise.resolve(),
    mode: "readonly",
  }),
});

// One read-only part of a participant's whole exam in the correction. Mounted
// lazily like the sample solution parts, so a long exam only builds the
// editors near the viewport and loads their images when they get close.
export const ExamReadOnlyPartViewer = createReactHook({
  name: "ExamReadOnlyPartViewer",
  lazy: true,
  minHeight: "160px",
  mapProps: (_hook, { initialContent }) => ({
    initialContent,
    save: () => Promise.resolve(),
    mode: "readonly",
  }),
  // The reserved height only holds the place until the content is there;
  // a short part must not keep the gap below it.
  afterRender: (hook) => {
    const observer = new MutationObserver(() => {
      if (hook.el.querySelector(".ProseMirror")?.offsetHeight > 0) {
        hook.el.style.minHeight = "";
        observer.disconnect();
      }
    });
    observer.observe(hook.el, { childList: true, subtree: true });
  },
});
