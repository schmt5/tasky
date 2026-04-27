import "../react/exam_content_editor.css";

export const ExamReadOnlyViewer = {
  async mounted() {
    const [ReactDOMClient, { default: ExamContentEditorComponent }] =
      await Promise.all([
        import("react-dom/client"),
        import("../react/ExamContentEditor"),
      ]);

    const createRoot =
      ReactDOMClient.createRoot ?? ReactDOMClient.default?.createRoot;

    const { content } = this.el.dataset;
    let initialContent = {};
    try {
      initialContent = content ? JSON.parse(content) : {};
    } catch (err) {
      console.error("ExamReadOnlyViewer: invalid content JSON", err);
    }

    this.root = createRoot(this.el);
    this.root.render(
      <ExamContentEditorComponent
        initialContent={initialContent}
        save={() => Promise.resolve()}
        editable={false}
        notFullWidth={true}
      />,
    );
  },

  destroyed() {
    if (this.root) {
      this.root.unmount();
      this.root = null;
    }
  },
};
