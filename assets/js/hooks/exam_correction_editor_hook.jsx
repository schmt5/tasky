import "../react/exam_content_editor.css";

export const ExamCorrectionEditor = {
  async mounted() {
    const [
      ReactDOMClient,
      { default: ExamContentEditorComponent },
      { saveExamCorrectionPart },
    ] = await Promise.all([
      import("react-dom/client"),
      import("../react/ExamContentEditor"),
      import("../react/api"),
    ]);

    const createRoot =
      ReactDOMClient.createRoot ?? ReactDOMClient.default?.createRoot;

    const { examId, submissionId, partId, content } = this.el.dataset;
    let initialContent = {};
    try {
      initialContent = content ? JSON.parse(content) : {};
    } catch (err) {
      console.error(
        "ExamCorrectionEditor: invalid initial content JSON",
        err,
      );
    }

    this.root = createRoot(this.el);
    this.root.render(
      <ExamContentEditorComponent
        initialContent={initialContent}
        save={(doc) =>
          saveExamCorrectionPart(
            examId,
            submissionId,
            partId,
            doc?.content ?? [],
          )
        }
        hideAnswers={true}
        correctionMode={true}
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
