import { useSyncExternalStore } from "react";
import { Toolbar } from "./ExamContentEditor";
import * as store from "./solutionEditorStore";

// Static stand-in with the same chrome/height while no editor is registered
// yet (Toolbar itself cannot render with a null editor).
function ToolbarPlaceholder() {
  return (
    <div className="exam-editor__toolbar">
      <div className="exam-editor__tabs">
        <div className="exam-editor__tabs-bar">
          <div className="exam-editor__tabs-list">
            <button
              type="button"
              className="exam-editor__tab"
              data-state="active"
              disabled
            >
              Start
            </button>
            <button type="button" className="exam-editor__tab" disabled>
              Tabellen
            </button>
          </div>
        </div>
        <div className="exam-editor__tab-content">
          <div
            className="exam-editor__toolbar-inner"
            style={{ visibility: "hidden" }}
          >
            <div className="exam-editor__group">
              <div className="exam-editor__group-btns">
                <button type="button" className="exam-editor__btn" disabled />
              </div>
              <span className="exam-editor__group-label">&nbsp;</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// The single toolbar of the Musterlösung view: bound to whichever part
// editor is active in the solutionEditorStore (focus switches it), so the
// user always sees one identical toolbar in one place.
export default function SharedSolutionToolbar() {
  const snap = useSyncExternalStore(store.subscribe, store.getSnapshot);

  return (
    <div className="exam-editor exam-editor--solution-mode exam-editor--shared-toolbar">
      {!snap.activeEditor || snap.activeEditor.isDestroyed ? (
        <ToolbarPlaceholder />
      ) : (
        <Toolbar
          editor={snap.activeEditor}
          status={snap.activeStatus.status}
          errorMsg={snap.activeStatus.errorMsg}
          hideAnswers={true}
          hideQuestion={true}
        />
      )}
    </div>
  );
}
