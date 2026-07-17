import "../react/exam_content_editor.css";

// Authoring editor for learning-unit (task) content. Reuses the exam content
// editor component unchanged — only the save/upload endpoints differ.
export const TaskContentEditor = {
  async mounted() {
    const [
      ReactDOMClient,
      { default: ExamContentEditorComponent },
      { saveTaskContent, uploadTaskImage },
    ] = await Promise.all([
      import("react-dom/client"),
      import("../react/ExamContentEditor"),
      import("../react/api"),
    ]);

    const createRoot =
      ReactDOMClient.createRoot ?? ReactDOMClient.default?.createRoot;

    const { taskId, content } = this.el.dataset;
    let initialContent = {};
    try {
      initialContent = content ? JSON.parse(content) : {};
    } catch (err) {
      console.error("TaskContentEditor: invalid initial content JSON", err);
    }

    this.root = createRoot(this.el);
    this.root.render(
      <ExamContentEditorComponent
        initialContent={initialContent}
        save={(doc) => saveTaskContent(taskId, doc)}
        uploadImage={(file) => uploadTaskImage(taskId, file)}
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
