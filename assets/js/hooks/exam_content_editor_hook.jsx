import "../react/exam_content_editor.css";

export const ExamContentEditor = {
  async mounted() {
    const [ReactDOMClient, { default: ExamContentEditorComponent }] =
      await Promise.all([
        import("react-dom/client"),
        import("../react/ExamContentEditor"),
      ]);

    const createRoot =
      ReactDOMClient.createRoot ?? ReactDOMClient.default?.createRoot;

    const { examId, content } = this.el.dataset;
    let initialContent = {};
    try {
      initialContent = content ? JSON.parse(content) : {};
    } catch (err) {
      console.error("ExamContentEditor: invalid initial content JSON", err);
    }

    this.root = createRoot(this.el);
    this.root.render(
      <ExamContentEditorComponent
        examId={examId}
        initialContent={initialContent}
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
