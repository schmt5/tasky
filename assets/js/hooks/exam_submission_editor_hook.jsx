import "../react/exam_content_editor.css";

const MIN_SPINNER_MS = 400;
const FLUSH_TIMEOUT_MS = 10000;

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export const ExamSubmissionEditor = {
  async mounted() {
    // Imperative handle into the React editor (set by ExamContentEditor once
    // mounted). Registered before the dynamic imports resolve so an early
    // "flush-before-submit" still gets an answer: no editor → nothing typed →
    // nothing unsaved.
    this.editorApi = { current: null };
    this.handleEvent("flush-before-submit", () => this.flushAndReport());

    const [
      ReactDOMClient,
      { default: ExamContentEditorComponent },
      { saveExamSubmissionContent },
    ] = await Promise.all([
      import("react-dom/client"),
      import("../react/ExamContentEditor"),
      import("../react/api"),
    ]);

    const createRoot =
      ReactDOMClient.createRoot ?? ReactDOMClient.default?.createRoot;

    const { examToken, content } = this.el.dataset;
    let initialContent = {};
    try {
      initialContent = content ? JSON.parse(content) : {};
    } catch (err) {
      console.error(
        "ExamSubmissionEditor: invalid initial content JSON",
        err,
      );
    }

    this.root = createRoot(this.el);
    this.root.render(
      <ExamContentEditorComponent
        initialContent={initialContent}
        save={(doc) => saveExamSubmissionContent(examToken, doc)}
        hideAnswers={true}
        apiRef={this.editorApi}
      />,
    );
  },

  // Submit-modal handshake: force-save everything pending, then report whether
  // the server now holds the student's full document. The modal blocks typing,
  // so a successful flush means the submit itself needs no content payload.
  async flushAndReport() {
    let ok = false;
    try {
      const api = this.editorApi.current;
      const flushed = api ? api.flush() : Promise.resolve(true);
      const [result] = await Promise.all([
        Promise.race([flushed, delay(FLUSH_TIMEOUT_MS).then(() => "timeout")]),
        delay(MIN_SPINNER_MS),
      ]);
      ok = result === true;
    } catch {
      ok = false;
    }
    this.pushEvent("submit_check_result", { ok });
  },

  destroyed() {
    if (this.root) {
      this.root.unmount();
      this.root = null;
    }
  },
};
