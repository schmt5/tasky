// The editor's mode presets — one named bundle per surface instead of a
// 10-flag prop matrix at every call site. Explicit props still override
// single flags (see ExamContentEditor).

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

  /** Student answering: content locked, only answer fields editable. */
  student: { hideAnswers: true, lockContent: true },

  /** One sample-solution part editor under the shared toolbar. */
  solution: {
    hideAnswers: true,
    hideQuestion: true,
    lockContent: true,
    notFullWidth: true,
    solutionMode: true,
    externalToolbar: true,
  },

  /** Teacher correcting one part of a submission. */
  correction: { hideAnswers: true, correctionMode: true, notFullWidth: true },

  /** Read-only rendering (print view, previews). */
  readonly: { editable: false, notFullWidth: true },
};
