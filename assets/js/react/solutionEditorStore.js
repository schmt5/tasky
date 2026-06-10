// Module-level store shared across the per-part editor React roots and the
// shared toolbar root in the Musterlösung view. Consumed via
// useSyncExternalStore — getSnapshot MUST return a referentially stable
// object between mutations, so the snapshot is cached and only rebuilt when
// something actually changes.

const editorsByPart = new Map();
const registrationOrder = [];
const statusByPart = {};
const listeners = new Set();

let activePartId = null;
let lockHintVisible = false;
let lockHintTimer = null;
let snapshot = buildSnapshot();

function buildSnapshot() {
  const activeStatus = statusByPart[activePartId] || {
    status: "idle",
    errorMsg: null,
  };

  return {
    activePartId,
    activeEditor: editorsByPart.get(activePartId) || null,
    activeStatus,
    lockHintVisible,
  };
}

function notify() {
  snapshot = buildSnapshot();
  listeners.forEach((listener) => listener());
}

export function subscribe(listener) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function getSnapshot() {
  return snapshot;
}

export function registerEditor(partId, editor) {
  editorsByPart.set(partId, editor);
  if (!registrationOrder.includes(partId)) registrationOrder.push(partId);
  // Bind the toolbar to the first registered editor so it is live before the
  // user focuses anything.
  if (activePartId === null) activePartId = partId;
  notify();
}

export function unregisterEditor(partId) {
  editorsByPart.delete(partId);
  const idx = registrationOrder.indexOf(partId);
  if (idx !== -1) registrationOrder.splice(idx, 1);
  delete statusByPart[partId];
  if (activePartId === partId) {
    activePartId = registrationOrder[0] ?? null;
  }
  notify();
}

export function setActive(partId) {
  if (activePartId === partId || !editorsByPart.has(partId)) return;
  activePartId = partId;
  notify();
}

// Blocked-edit hint for the shared toolbar: the veto happens inside a part
// editor's React root, but the pill is rendered by the toolbar root, so the
// flash state crosses roots through this store. Mirrors the 2400 ms timing of
// the per-editor hint in ExamContentEditor.
export function flashLockHint() {
  if (lockHintTimer) clearTimeout(lockHintTimer);
  lockHintTimer = setTimeout(() => {
    lockHintTimer = null;
    lockHintVisible = false;
    notify();
  }, 2400);
  if (!lockHintVisible) {
    lockHintVisible = true;
    notify();
  }
}

export function setStatus(partId, status, errorMsg = null) {
  const current = statusByPart[partId];
  if (current && current.status === status && current.errorMsg === errorMsg) {
    return;
  }
  statusByPart[partId] = { status, errorMsg };
  if (partId === activePartId) notify();
}
