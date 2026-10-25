// Keeps the teacher's place when switching between the "Inhalt" and
// "Musterlösung" tabs of the exam editor.
//
// A pixel offset does not carry over: the sample solution fills the answer
// fields, so the two pages have different heights. The document skeleton
// does — the solution is the content with the answers merged in — so a place
// is recorded as (part, top-level block within the part, optional answerId)
// plus the screen height it sat at. On a tab click the anchor is appended to
// the link's href; the other tab scrolls the same element to the same height.
// Being in the URL, the anchor also survives a reload.
//
// The caret wins: if it is on screen, it is the anchor and is put back at the
// same spot. Otherwise the first block starting below the sticky chrome is.

const TABS = ["inhalt", "musterloesung"];
const PARAMS = ["part", "block", "answer", "caret", "y"];
const CHROME =
  "#content-page-header, .exam-editor__toolbar, [id^='solution-toolbar-']";
const SOLUTION_PART = "[id^='sample-solution-part-editor-']";
const CONTENT_EDITOR = "[id^='exam-content-editor-'] .ProseMirror";
// Editors mount asynchronously; images and lazy part editors keep shifting
// the layout for a moment after that, so the alignment is held a little.
const WAIT_MS = 5000;
const ALIGN_MS = 1500;
const USER_INPUT = ["wheel", "touchstart", "keydown", "mousedown"];

export const TabAnchor = {
  mounted() {
    this.lastView = null;
    this.token = null;

    // The tab click blurs the editor before it fires, so remember which
    // editor held the caret last. ProseMirror keeps its selection on blur.
    this.onFocusIn = (e) => {
      const view = e.target.closest?.(".ProseMirror")?.editor?.view;
      if (view) this.lastView = view;
    };

    // Runs before LiveView's own handler on window, which reads the href.
    this.onClick = (e) => {
      const link = e.target.closest("a[href]");
      if (!link) return;

      const url = new URL(link.href);
      const target = url.searchParams.get("tab");
      const current = currentTab();
      if (!TABS.includes(target) || !TABS.includes(current) || target === current)
        return;

      for (const key of PARAMS) url.searchParams.delete(key);
      const anchor = this.capture();
      if (anchor) {
        for (const [key, value] of Object.entries(anchor)) {
          if (value != null) url.searchParams.set(key, value);
        }
      }
      link.href = url.toString();
    };

    this.onPatched = (e) => {
      if (e.detail?.kind === "patch") this.restore();
    };

    // Any scroll or typing of the teacher's own ends the alignment.
    this.onUserInput = () => {
      this.token = null;
    };

    document.addEventListener("focusin", this.onFocusIn);
    this.el.addEventListener("click", this.onClick);
    window.addEventListener("phx:page-loading-stop", this.onPatched);
    for (const type of USER_INPUT) {
      window.addEventListener(type, this.onUserInput, { passive: true });
    }

    this.restore();
  },

  destroyed() {
    this.token = null;
    document.removeEventListener("focusin", this.onFocusIn);
    window.removeEventListener("phx:page-loading-stop", this.onPatched);
    for (const type of USER_INPUT) {
      window.removeEventListener(type, this.onUserInput);
    }
  },

  capture() {
    const top = chromeBottom();
    return this.caretAnchor(top) || firstVisibleAnchor(top);
  },

  caretAnchor(top) {
    const view = this.lastView;
    if (!view || !view.dom.isConnected) return null;

    const { head } = view.state.selection;
    let y;
    try {
      y = view.coordsAtPos(head).top;
    } catch {
      return null;
    }
    if (y < top || y > window.innerHeight) return null;

    const place = caretPlace(view, head);
    return place && { ...place, y: Math.round(y) };
  },

  async restore() {
    const params = new URL(window.location.href).searchParams;
    const part = params.get("part");
    if (!part) return;

    const token = (this.token = {});
    const live = () => this.token === token;
    const block = parseInt(params.get("block"), 10) || 0;
    const answer = params.get("answer");
    const caret = params.get("caret");
    let y = parseInt(params.get("y"), 10);

    const found = await waitFor(() => findPart(part, y), live);
    if (!found) return;
    const { view, start } = found;

    const { doc } = view.state;
    const index = Math.min(start + block, doc.childCount - 1);
    let offset = 0;
    for (let i = 0; i < index; i++) offset += doc.child(i).nodeSize;
    const node = doc.child(index);

    let element = view.nodeDOM(offset);
    let caretPos = null;

    const answerAt = answer ? findAnswer(doc, answer) : null;
    if (answerAt) {
      element = view.nodeDOM(answerAt.pos);
      caretPos = answerAt.pos + answerAt.node.nodeSize - 1;
    } else if (caret != null) {
      caretPos = Math.min(
        Math.max(offset + (parseInt(caret, 10) || 0), offset + 1),
        offset + node.nodeSize - 1,
      );
    }

    let measure = () => element?.getBoundingClientRect().top;

    if (caretPos != null && caret != null) {
      // Loaded lazily like the editor itself, so it stays out of app.js.
      const { Selection } = await import("@tiptap/pm/state");
      if (!live()) return;
      const selection = Selection.near(view.state.doc.resolve(caretPos), -1);
      view.dispatch(view.state.tr.setSelection(selection));
      view.focus();
      measure = () => view.coordsAtPos(view.state.selection.head).top;
      // The caret must not end up under a taller toolbar than before.
      y = Math.max(y, chromeBottom() + 8);
    }

    if (Number.isNaN(y)) y = chromeBottom() + 8;
    align(measure, y, live);
  },
};

function currentTab() {
  return new URL(window.location.href).searchParams.get("tab") || "inhalt";
}

// Bottom edge of the sticky header and toolbar — content above it is hidden.
function chromeBottom() {
  let bottom = 0;
  for (const el of document.querySelectorAll(CHROME)) {
    const rect = el.getBoundingClientRect();
    if (rect.height && rect.top < window.innerHeight / 2) {
      bottom = Math.max(bottom, rect.bottom);
    }
  }
  return bottom;
}

function mountedViews() {
  return [...document.querySelectorAll(".ProseMirror")]
    .map((el) => el.editor?.view)
    .filter(Boolean);
}

// (part, block) of a top-level node. A solution editor holds exactly one
// part; the content editor holds them all, each starting at its question
// heading. Preamble blocks above the first question have no part.
function partOf(view, index) {
  const container = view.dom.closest(SOLUTION_PART);
  if (container) return { part: container.dataset.partId, block: index };

  const { doc } = view.state;
  for (let i = index; i >= 0; i--) {
    const node = doc.child(i);
    if (isQuestion(node) && node.attrs.partId) {
      return { part: node.attrs.partId, block: index - i };
    }
  }
  return null;
}

function isQuestion(node) {
  return node.type.name === "heading" && node.attrs.level === 3;
}

function caretPlace(view, pos) {
  const $pos = view.state.doc.resolve(pos);
  if ($pos.depth === 0) return null;

  const owner = partOf(view, $pos.index(0));
  if (!owner) return null;

  // Inside an answer field the field itself is the anchor: its text differs
  // between the tabs, so the caret goes to its end.
  for (let depth = $pos.depth; depth > 0; depth--) {
    const answer = $pos.node(depth).attrs.answerId;
    if (answer) return { ...owner, answer, caret: "end" };
  }
  return { ...owner, caret: pos - $pos.before(1) };
}

function firstVisibleAnchor(top) {
  let straddling = null;

  for (const view of mountedViews()) {
    const { doc } = view.state;
    let offset = 0;
    for (let index = 0; index < doc.childCount; index++) {
      const dom = view.nodeDOM(offset);
      offset += doc.child(index).nodeSize;
      if (!(dom instanceof HTMLElement)) continue;

      const rect = dom.getBoundingClientRect();
      if (rect.bottom <= top) continue;
      if (rect.top >= window.innerHeight) break;

      const owner = partOf(view, index);
      if (!owner) continue;
      if (rect.top >= top) return { ...owner, y: Math.round(rect.top) };
      straddling ??= { ...owner, y: Math.round(rect.top) };
    }
  }

  // One block taller than the screen: keep its partial offset.
  return straddling;
}

// The editor and the index of the part's first block in it, once mounted.
// A solution part editor mounts only near the viewport, so its placeholder
// is scrolled into place first.
function findPart(part, y) {
  const container = document.querySelector(
    `${SOLUTION_PART}[data-part-id="${CSS.escape(part)}"]`,
  );
  if (container) {
    const view = container.querySelector(".ProseMirror")?.editor?.view;
    if (view) return { view, start: 0 };
    if (!container.dataset.anchorScrolled) {
      container.dataset.anchorScrolled = "true";
      const top = Number.isNaN(y) ? chromeBottom() : y;
      scrollByInstant(container.getBoundingClientRect().top - top);
    }
    return null;
  }

  const view = document.querySelector(CONTENT_EDITOR)?.editor?.view;
  if (!view) return null;

  const { doc } = view.state;
  for (let i = 0; i < doc.childCount; i++) {
    const node = doc.child(i);
    if (isQuestion(node) && node.attrs.partId === part) return { view, start: i };
  }
  // The question is gone (deleted meanwhile): nothing to anchor to.
  return false;
}

function findAnswer(doc, answerId) {
  let found = null;
  doc.descendants((node, pos) => {
    if (found) return false;
    if (node.attrs.answerId === answerId) {
      found = { node, pos };
      return false;
    }
  });
  return found;
}

function waitFor(fn, live) {
  const deadline = performance.now() + WAIT_MS;
  return new Promise((resolve) => {
    const tick = () => {
      if (!live()) return resolve(null);
      const result = fn();
      if (result || result === false) return resolve(result || null);
      if (performance.now() > deadline) return resolve(null);
      requestAnimationFrame(tick);
    };
    tick();
  });
}

function align(measure, y, live) {
  const deadline = performance.now() + ALIGN_MS;
  const step = () => {
    if (!live()) return;
    const top = measure();
    if (top != null && Math.abs(top - y) >= 1) scrollByInstant(top - y);
    if (performance.now() < deadline) requestAnimationFrame(step);
  };
  step();
}

function scrollByInstant(delta) {
  window.scrollBy({ top: delta, behavior: "instant" });
}
