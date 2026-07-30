// Print-readiness signal for Gotenberg (PDF export). Lives in the bundle
// instead of an inline <script> so the Content-Security-Policy can stay
// strict (script-src 'self'). Activates only on pages that render the
// #print-ready-signal marker (the print view).
//
// Readiness is gated on real signals instead of a fixed timeout: every
// read-only viewer root must have committed its first render (the hook sets
// data-print-rendered, see exam_readonly_viewer_hook.jsx), then all images
// must finish loading so they aren't cut from the PDF. A generous fallback
// deadline keeps the export alive even if a viewer never signals (e.g. its
// chunk fails to load) — Gotenberg then renders whatever is there instead
// of timing out the whole run.
const POLL_INTERVAL_MS = 100;
const FALLBACK_DEADLINE_MS = 20000;

export function initPrintReady() {
  if (!document.getElementById("print-ready-signal")) return;

  window.printReady = false;
  const startedAt = Date.now();

  function viewersReady() {
    const viewers = document.querySelectorAll('[phx-hook="ExamReadOnlyViewer"]');
    return Array.prototype.every.call(
      viewers,
      (el) => el.getAttribute("data-print-rendered") === "true",
    );
  }

  function imagesLoaded() {
    const imgs = Array.prototype.slice.call(document.images);
    return Promise.all(
      imgs.map(function (img) {
        if (img.complete) return Promise.resolve();
        return new Promise(function (resolve) {
          img.addEventListener("load", resolve, { once: true });
          img.addEventListener("error", resolve, { once: true });
        });
      }),
    );
  }

  function poll() {
    const deadlineHit = Date.now() - startedAt > FALLBACK_DEADLINE_MS;

    if (viewersReady() || deadlineHit) {
      imagesLoaded().then(function () {
        window.requestAnimationFrame(function () {
          window.requestAnimationFrame(function () {
            window.printReady = true;
          });
        });
      });
    } else {
      setTimeout(poll, POLL_INTERVAL_MS);
    }
  }

  poll();
}
