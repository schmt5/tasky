// The editor's mode presets — one named bundle per surface instead of a
// 10-flag prop matrix at every call site. A preset OVERRIDES the matching
// explicit prop (see ExamContentEditor), so a surface that needs a different
// flag combination gets its own preset rather than a call-site override.

export interface EditorModePreset {
  hideAnswers?: boolean;
  lockContent?: boolean;
  correctionMode?: boolean;
  notFullWidth?: boolean;
  hideQuestion?: boolean;
  editable?: boolean;
  solutionMode?: boolean;
  externalToolbar?: boolean;
}

export const EDITOR_MODES: Record<string, EditorModePreset> = {
  /** Teacher authoring the exam/task content. */
  author: {},

  /**
   * Student answering: content locked, only answer fields editable.
   *
   * `hideQuestion` matters here: the "Frage" button inserts a question heading,
   * which is the teacher's authoring control. On a locked document it either
   * does nothing or turns the learner's own answer into a heading — it has no
   * business being in the exam toolbar.
   */
  student: { hideAnswers: true, hideQuestion: true, lockContent: true },

  /** One sample-solution part editor under the shared toolbar. */
  solution: {
    hideAnswers: true,
    hideQuestion: true,
    lockContent: true,
    notFullWidth: true,
    solutionMode: true,
    externalToolbar: true,
  },

  /**
   * Teacher filling in the model answers of a whole learning unit.
   *
   * Same lock as the exam `solution` preset, but without `externalToolbar` /
   * `notFullWidth`: a learning unit has no parts, so there is a single editor
   * and nothing to share a toolbar between.
   */
  taskSolution: {
    hideAnswers: true,
    hideQuestion: true,
    lockContent: true,
    solutionMode: true,
  },

  /** Teacher correcting one part of a submission. */
  correction: { hideAnswers: true, correctionMode: true, notFullWidth: true },

  /**
   * Teacher annotating a learner's answer document of a whole learning unit.
   *
   * Unlike the exam `correction` preset this keeps the full-width layout —
   * the task correction page has no points sidebar to make room for.
   */
  taskCorrection: { correctionMode: true },

  /** Read-only rendering (print view, previews). */
  readonly: { editable: false, notFullWidth: true },
};
