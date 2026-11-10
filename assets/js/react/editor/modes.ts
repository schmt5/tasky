// The editor's mode presets — one named bundle per surface instead of a
// 10-flag prop matrix at every call site. A preset OVERRIDES the matching
// explicit prop (see ExamContentEditor), so a surface that needs a different
// flag combination gets its own preset rather than a call-site override.

export interface EditorModePreset {
  /** Hide the toolbar controls that CREATE answer fields. */
  hideAnswers?: boolean;
  /** Load PreventNodeDeletion: existing answer fields cannot be removed. */
  protectAnswers?: boolean;
  /** Hide the "Blöcke" toolbar group (Hinweisbox and Zitat). */
  hideCallout?: boolean;
  lockContent?: boolean;
  correctionMode?: boolean;
  notFullWidth?: boolean;
  hideQuestion?: boolean;
  editable?: boolean;
  solutionMode?: boolean;
  externalToolbar?: boolean;
  /**
   * Editable, but with no toolbar at all. Distinct from `externalToolbar`,
   * which means "the toolbar lives elsewhere" and is wired into
   * `solutionEditorStore`.
   */
  hideToolbar?: boolean;
  /** Load PaperAnswerLines: Enter/Backspace size an answer box. */
  paperMode?: boolean;
  /**
   * One plain toolbar row without tabs and without the grey bar: the start
   * tools plus the teacher comment. For the exam correction, where verdicts
   * are given in the power panel beside the editor, not in the text.
   */
  compactToolbar?: boolean;
}

export const EDITOR_MODES: Record<string, EditorModePreset> = {
  /** Teacher authoring the exam/task content. */
  author: {},

  // There is no learner preset for answer-field documents: learners answer in
  // native fields (TaskyWeb.ExamDocHTML + the ExamAnswersForm hook), not in
  // Tiptap.

  /**
   * Free-document exam (`answer_mode: "free_document"`): no answer fields and
   * no question headings, but the whole document is editable.
   *
   * ONE preset for BOTH sides — teacher and learner. Nothing about the editing
   * rules differs between them here; the only difference is `uploadImage`,
   * which only the authoring hook passes, so the "Einfügen" group appears for
   * the teacher and not for the learner.
   */
  freeDocument: { hideAnswers: true, hideQuestion: true },

  /**
   * One sample-solution part editor under the shared toolbar — the same for
   * an exam question and a learning-unit question.
   */
  solution: {
    hideAnswers: true,
    protectAnswers: true,
    hideCallout: true,
    hideQuestion: true,
    lockContent: true,
    notFullWidth: true,
    solutionMode: true,
    externalToolbar: true,
  },

  /** Teacher correcting one part of a submission. */
  correction: {
    hideAnswers: true,
    protectAnswers: true,
    hideCallout: true,
    correctionMode: true,
    notFullWidth: true,
    // A question heading typed into a submission would re-split its parts.
    hideQuestion: true,
    compactToolbar: true,
  },

  /**
   * Teacher annotating a learner's answer document of a whole learning unit.
   *
   * Unlike the exam `correction` preset this keeps the full-width layout —
   * the task correction page has no points sidebar to make room for.
   */
  taskCorrection: { correctionMode: true },

  /**
   * Teacher sizing the paper version: the content is locked and only the
   * answer boxes grow and shrink (Enter / Backspace).
   *
   * The lock is the same one the sample solution gets — `stripAnswers` keeps
   * answer content out of the skeleton `LockExamContent` compares, so typing
   * inside an answer field is exactly what passes and nothing else does. An
   * `answerBlock` is `block+` and "empty" already means "one paragraph", so
   * pressing Enter genuinely adds a writing line; no extra machinery.
   *
   * No toolbar: the only gesture here is Enter, and formatting a blank sheet
   * would be meaningless.
   */
  paper: {
    hideAnswers: true,
    protectAnswers: true,
    hideCallout: true,
    hideQuestion: true,
    lockContent: true,
    hideToolbar: true,
    // On paper there is no sheet floating on a canvas — the sheet *is* the
    // page. Full-width mode would paint the grey canvas and a drop shadow
    // behind the document, and its rules out-specify the paper stylesheet.
    notFullWidth: true,
    paperMode: true,
  },

  /** Read-only rendering (print view, previews). */
  readonly: { editable: false, notFullWidth: true },
};
