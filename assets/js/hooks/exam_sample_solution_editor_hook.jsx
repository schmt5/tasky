import "../react/exam_content_editor.css";

// One editor per exam part, stacked in the Musterlösung view. Editors are
// lazy-mounted via IntersectionObserver so exams with many parts stay fast:
// the React/Tiptap instance is only created once the part scrolls within
// ~700px of the viewport, and stays mounted afterwards (mount-once).
const LAZY_ROOT_MARGIN = "700px 0px 700px 0px";

export const ExamSampleSolutionPartEditor = {
  mounted() {
    // Reserve height so layout/scroll geometry is stable before mount.
    this.el.style.minHeight = "320px";

    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          this.observer.disconnect();
          this.observer = null;
          this.mountEditor();
        }
      },
      { rootMargin: LAZY_ROOT_MARGIN },
    );
    this.observer.observe(this.el);
  },

  async mountEditor() {
    if (this.mountStarted) return;
    this.mountStarted = true;

    const [
      ReactDOMClient,
      { default: ExamContentEditorComponent },
      { saveExamSampleSolutionPart },
    ] = await Promise.all([
      import("react-dom/client"),
      import("../react/ExamContentEditor"),
      import("../react/api"),
    ]);

    // The element may have been removed while the imports were in flight.
    if (this.destroyedFlag) return;

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
        hideQuestion={true}
        lockContent={true}
        notFullWidth={true}
        solutionMode={true}
        externalToolbar={true}
        partId={partId}
      />,
    );
  },

  destroyed() {
    this.destroyedFlag = true;
    if (this.observer) {
      this.observer.disconnect();
      this.observer = null;
    }
    if (this.root) {
      this.root.unmount();
      this.root = null;
    }
  },
};
