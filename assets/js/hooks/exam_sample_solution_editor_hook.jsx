import "../react/exam_content_editor.css";

export const ExamSampleSolutionPartEditor = {
  async mounted() {
    const [
      ReactDOMClient,
      { default: ExamContentEditorComponent },
      { saveExamSampleSolutionPart },
    ] = await Promise.all([
      import("react-dom/client"),
      import("../react/ExamContentEditor"),
      import("../react/api"),
    ]);

    const createRoot =
      ReactDOMClient.createRoot ?? ReactDOMClient.default?.createRoot;

    const { examId, partId, content } = this.el.dataset;
    let initialContent = {};
    try {
      initialContent = content ? JSON.parse(content) : {};
    } catch (err) {
      console.error(
        "ExamSampleSolutionPartEditor: invalid initial content JSON",
        err,
      );
    }

    this.root = createRoot(this.el);
    this.root.render(
      <ExamContentEditorComponent
        initialContent={initialContent}
        save={(doc) =>
          saveExamSampleSolutionPart(examId, partId, doc?.content ?? [])
        }
        hideAnswers={true}
        hidePageBreak={true}
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
