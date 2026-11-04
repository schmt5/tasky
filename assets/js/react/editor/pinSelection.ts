// Which pin is selected on which pin image, shared between the pin images in
// a sample-solution editor (extensions/imagePin.ts) and the "Pins" section of
// the question's card next to it (react/PinPanel.jsx), which live in
// different React roots. Keyed by the editor, so two questions never share a
// selection; the pin image by its `answerId`, which survives every edit.

const byEditor = new WeakMap<object, { answerId: string | null; indexes: Map<string, number> }>();
const listeners = new Set<() => void>();
let version = 0;

function entry(editor: object) {
  let e = byEditor.get(editor);
  if (!e) {
    e = { answerId: null, indexes: new Map() };
    byEditor.set(editor, e);
  }
  return e;
}

export function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

/** Changes whenever any selection does — a useSyncExternalStore snapshot. */
export function getVersion() {
  return version;
}

/** Makes `answerId` the pin image the card steers, with pin `index` picked. */
export function select(editor: object, answerId: string, index: number) {
  const e = entry(editor);
  if (e.answerId === answerId && e.indexes.get(answerId) === index) return;
  e.answerId = answerId;
  e.indexes.set(answerId, index);
  version += 1;
  listeners.forEach((l) => l());
}

/** The pin image the card steers; null until one is clicked (then: the first). */
export function activeImage(editor: object): string | null {
  return byEditor.get(editor)?.answerId ?? null;
}

/** The picked pin of one pin image. */
export function selectedIndex(editor: object, answerId: string): number {
  return byEditor.get(editor)?.indexes.get(answerId) ?? 0;
}
