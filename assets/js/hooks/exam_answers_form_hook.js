import { createAutosave } from "../autosave";
import { saveAnswerFields } from "../react/api";
import { flushAndReport } from "./create_react_hook";

// The learner's answer sheet: the exam or learning unit rendered as plain
// HTML by the server (TaskyWeb.ExamDocHTML), with native fields for the
// answers. This hook collects their values and autosaves them — the same
// engine as the Tiptap editors, so debounce, retry, keepalive and the
// flush-before-submit handshake behave exactly alike.
//
// Saving goes over HTTP, not the LiveView socket: a learner keeps working and
// saving while the socket reconnects. The container is phx-update="ignore",
// so a LiveView re-render never resets what was typed.
//
// Without `data-save-url` (read-back view, teacher preview) the fields only
// size themselves and nothing is sent.

const STATUS_TEXT = {
  idle: "",
  saving: "Speichert …",
  saved: "Gespeichert",
};

// `field-sizing: content` lets gaps and answer blocks grow with their text in
// CSS alone. Where it is missing, the hook sizes them by hand.
const NATIVE_SIZING =
  typeof CSS !== "undefined" && CSS.supports?.("field-sizing", "content");

export const ExamAnswersForm = {
  mounted() {
    // `flushAndReport` reads the engine through this ref, like the editors'.
    this.editorApi = { current: null };
    this.handleEvent("flush-before-submit", () => flushAndReport(this));

    if (!NATIVE_SIZING) {
      this.el.querySelectorAll(".exam-doc__block, .exam-doc__gap").forEach(fitField);
    }

    this.onInput = (event) => {
      const field = event.target;
      if (!NATIVE_SIZING && field.matches?.(".exam-doc__block, .exam-doc__gap")) {
        fitField(field);
      }
      if (this.engine && isAnswerField(field)) this.engine.schedule(this.snapshot());
    };
    this.el.addEventListener("input", this.onInput);
    this.el.addEventListener("change", this.onInput);

    const url = this.el.dataset.saveUrl;
    if (!url) return;

    const statusEl = this.el.querySelector("[data-save-status]");
    this.engine = createAutosave(
      (payload, opts) => saveAnswerFields(url, payload, opts),
      (status, errorMsg) => {
        if (!statusEl) return;
        statusEl.dataset.state = status;
        statusEl.textContent =
          status === "error" ? errorMsg || "Speichern fehlgeschlagen" : STATUS_TEXT[status];
      },
    );
    this.editorApi.current = { flush: this.engine.flush };
  },

  // Every field, every time: the server merges the payload over what it holds,
  // so a full snapshot is idempotent and a lost request heals with the next.
  snapshot() {
    const answers = {};
    const choices = {};

    this.el.querySelectorAll("[data-answer-id]").forEach((field) => {
      answers[field.dataset.answerId] =
        field.type === "checkbox" ? field.checked : field.value;
    });

    this.el.querySelectorAll("input[type=radio][data-group-id]").forEach((radio) => {
      const group = radio.dataset.groupId;
      if (radio.checked) choices[group] = radio.value;
      else if (!(group in choices)) choices[group] = null;
    });

    return { answers, choices };
  },

  destroyed() {
    this.el.removeEventListener("input", this.onInput);
    this.el.removeEventListener("change", this.onInput);
    if (this.engine) this.engine.destroy();
    this.editorApi.current = null;
  },
};

function isAnswerField(el) {
  return el.matches?.("[data-answer-id], [data-group-id]");
}

function fitField(field) {
  if (field.tagName === "TEXTAREA") {
    field.style.height = "auto";
    field.style.height = `${field.scrollHeight + 2}px`;
  } else {
    field.style.width = `${Math.max(field.value.length + 2, 6)}ch`;
  }
}
