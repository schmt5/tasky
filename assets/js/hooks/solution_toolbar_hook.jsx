import "../react/exam_content_editor.css";

// Mounts the single shared toolbar for the Musterlösung view. All React
// logic lives in SharedSolutionToolbar (static imports — esbuild's dynamic
// import("react") has no named exports, so hooks must not destructure it).
export const SolutionToolbar = {
  async mounted() {
    const [ReactDOMClient, { default: SharedSolutionToolbar }] =
      await Promise.all([
        import("react-dom/client"),
        import("../react/SharedSolutionToolbar"),
      ]);

    const createRoot =
      ReactDOMClient.createRoot ?? ReactDOMClient.default?.createRoot;

    this.root = createRoot(this.el);
    this.root.render(<SharedSolutionToolbar />);
  },

  destroyed() {
    if (this.root) {
      this.root.unmount();
      this.root = null;
    }
  },
};
