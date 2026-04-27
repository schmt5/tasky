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
      console.error("ExamCorrectionEditor: invalid initial content JSON", err);
    }

    // Store a ref to the container element for dispatching DOM events
    this._containerRef = { current: this.el };

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
        containerRef={this._containerRef}
      />,
    );

    // Listen for server-pushed content reload (e.g. after AI correction)
    this.handleEvent("reload-content", ({ content: json }) => {
      let newContent = {};
      try {
        newContent = json ? JSON.parse(json) : {};
      } catch (err) {
        console.error("ExamCorrectionEditor: invalid reload content JSON", err);
      }
      // Dispatch a custom DOM event that the TipTap editor listens for
      this.el.dispatchEvent(
        new CustomEvent("tiptap:setContent", { detail: newContent }),
      );
    });
  },

  destroyed() {
    if (this.root) {
      this.root.unmount();
      this.root = null;
    }
  },
};
