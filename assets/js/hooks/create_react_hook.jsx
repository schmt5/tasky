import "../react/exam_content_editor.css";

// Factory for the React-island LiveView hooks. Owns the boilerplate every
// island repeats — dynamic imports, createRoot, data-content parsing,
// unmount — plus the two failure modes ad-hoc copies kept getting wrong:
//
//   * destroyed-after-await: the element can be removed while the dynamic
//     imports are in flight; rendering then would leak a React root.
//   * corrupt data-content JSON: mounting an EMPTY editor would let the next
//     autosave overwrite the server copy — fail loudly and refuse to mount.
//
// Config:
//   * name          — hook name for error messages
//   * loadComponent — () => import(...) for the root component
//                     (defaults to the ExamContentEditor)
//   * mapProps      — (hook, {dataset, initialContent, api}) => props;
//                     `api` is the ../react/api module
//   * lazy          — mount via IntersectionObserver when scrolled near
//   * minHeight     — reserved height for lazy islands (stable geometry)
//   * setup         — runs first in mounted() (register early handleEvent)
//   * afterRender   — runs after the first render call
//   * methods       — extra methods merged onto the hook object

const LAZY_ROOT_MARGIN = "700px 0px 700px 0px";
const MIN_SPINNER_MS = 400;
const FLUSH_TIMEOUT_MS = 10000;

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export function createReactHook({
  name,
  loadComponent = () => import("../react/ExamContentEditor"),
  mapProps,
  lazy = false,
  minHeight = null,
  setup = null,
  afterRender = null,
  methods = {},
}) {
  return {
    ...methods,

    mounted() {
      if (setup) setup(this);

      if (lazy) {
        if (minHeight) this.el.style.minHeight = minHeight;

        this.observer = new IntersectionObserver(
          (entries) => {
            if (entries.some((entry) => entry.isIntersecting)) {
              this.observer.disconnect();
              this.observer = null;
              this.mountIsland();
            }
          },
          { rootMargin: LAZY_ROOT_MARGIN },
        );
        this.observer.observe(this.el);
      } else {
        this.mountIsland();
      }
    },

    async mountIsland() {
      if (this.mountStarted) return;
      this.mountStarted = true;

      const [ReactDOMClient, { default: Component }, api] = await Promise.all([
        import("react-dom/client"),
        loadComponent(),
        import("../react/api"),
      ]);

      // The element may have been removed while the imports were in flight.
      if (this.destroyedFlag) return;

      const createRoot =
        ReactDOMClient.createRoot ?? ReactDOMClient.default?.createRoot;

      const initialContent = parseContent(name, this.el);
      if (initialContent === null) return;

      this.root = createRoot(this.el);
      this.root.render(
        <Component
          {...mapProps(this, { dataset: this.el.dataset, initialContent, api })}
        />,
      );

      if (afterRender) afterRender(this);
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
}

// Submit-modal handshake shared by the student editors: force-save everything
// pending, then report whether the server now holds the full document. The
// modal blocks typing, so a successful flush means the submit itself needs no
// content payload.
export async function flushAndReport(hook) {
  let ok = false;
  try {
    const api = hook.editorApi.current;
    const flushed = api ? api.flush() : Promise.resolve(true);
    const [result] = await Promise.all([
      Promise.race([flushed, delay(FLUSH_TIMEOUT_MS).then(() => "timeout")]),
      delay(MIN_SPINNER_MS),
    ]);
    ok = result === true;
  } catch {
    ok = false;
  }
  hook.pushEvent("submit_check_result", { ok });
}

function parseContent(name, el) {
  const raw = el.dataset.content;
  if (raw === undefined) return {};

  try {
    return raw ? JSON.parse(raw) : {};
  } catch (err) {
    console.error(
      `${name}: invalid data-content JSON — refusing to mount an empty editor` +
        " (its next autosave would overwrite the server copy)",
      err,
    );

    el.innerHTML =
      '<div class="p-4 text-sm font-medium text-red-700 bg-red-50 border ' +
      'border-red-200 rounded-lg">Inhalt konnte nicht geladen werden. ' +
      "Bitte die Seite neu laden und nicht weiterarbeiten.</div>";
    return null;
  }
}
