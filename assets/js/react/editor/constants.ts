export const AUTOSAVE_DELAY_MS = 1000;

// Backoff schedule for failed saves; the last entry repeats indefinitely so a
// student with flaky Wi-Fi keeps retrying until the exam ends.
export const RETRY_DELAYS_MS = [2000, 4000, 8000, 15000];

// HTTP statuses where retrying can never succeed (submitted / exam ended /
// rejected payload / session expired) — give up instead of hammering the
// server. Errors flagged `permanent` by the API layer (login-page redirects)
// stop retrying too.
export const PERMANENT_SAVE_ERRORS = [400, 401, 403, 404, 409, 422];

export interface ColorOption {
  name: string;
  value: string;
}

export const HIGHLIGHT_COLORS: ColorOption[] = [
  { name: "Rot", value: "#fecaca" },
  { name: "Orange", value: "#fed7aa" },
  { name: "Gelb", value: "#fef08a" },
  { name: "Grün", value: "#bbf7d0" },
  { name: "Blau", value: "#bfdbfe" },
  { name: "Lila", value: "#e9d5ff" },
];

// "Rot" is intentionally omitted — red is reserved for sample-solution model
// answers (rendered red automatically), so teachers can't pick it for content.
export const TEXT_COLORS: ColorOption[] = [
  { name: "Orange", value: "#ea580c" },
  { name: "Gelb", value: "#ca8a04" },
  { name: "Grün", value: "#16a34a" },
  { name: "Blau", value: "#2563eb" },
  { name: "Lila", value: "#9333ea" },
];

// Callout ("Hinweisbox") palette. Only the token lands in the document; the
// hex values live in the toolbar and the stylesheet, so the palette can be
// retuned without touching stored docs.
export type CalloutColor = "red" | "yellow" | "green" | "blue" | "violet";

export const CALLOUT_COLOR_VALUES: readonly CalloutColor[] = [
  "red",
  "yellow",
  "green",
  "blue",
  "violet",
];

export const DEFAULT_CALLOUT_COLOR: CalloutColor = "yellow";

// `swatch` only paints the toolbar chip — it mirrors the border colour of the
// corresponding `.callout[data-color]` rule in exam_content_editor.css.
export const CALLOUT_COLORS: Array<{
  name: string;
  value: CalloutColor;
  swatch: string;
}> = [
  { name: "Rot", value: "red", swatch: "#f87171" },
  { name: "Gelb", value: "yellow", swatch: "#facc15" },
  { name: "Grün", value: "green", swatch: "#4ade80" },
  { name: "Blau", value: "blue", swatch: "#60a5fa" },
  { name: "Lila", value: "violet", swatch: "#a78bfa" },
];
