import "../react/exam_content_editor.css";

export const ExamContentEditor = {
  async mounted() {
    const [
      ReactDOMClient,
      { default: ExamContentEditorComponent },
      { saveExamContent, uploadExamImage },
    ] = await Promise.all([
      import("react-dom/client"),
      import("../react/ExamContentEditor"),
      import("../react/api"),
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
        initialContent={initialContent}
        save={(doc) => saveExamContent(examId, doc)}
        uploadImage={(file) => uploadExamImage(examId, file)}
        placeholder="Beginne mit einer Überschrift …"
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
