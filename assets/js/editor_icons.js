// Icons both editors draw: the teachers' React toolbar (react/editor/icons.tsx)
// and the learners' essay field (rich_answer_field.js), which runs without
// React. Drawn like the heroicons outline set they sit next to: 24×24 grid,
// 1.5 stroke, round caps.

export const EDITOR_ICONS = {
  bulletList: [
    {
      tag: "circle",
      cx: 5,
      cy: 6,
      r: 1.25,
      fill: "currentColor",
      stroke: "none",
    },
    {
      tag: "circle",
      cx: 5,
      cy: 12,
      r: 1.25,
      fill: "currentColor",
      stroke: "none",
    },
    {
      tag: "circle",
      cx: 5,
      cy: 18,
      r: 1.25,
      fill: "currentColor",
      stroke: "none",
    },
    { tag: "path", d: "M9.5 6H20M9.5 12H20M9.5 18H20" },
  ],
  // The digits are paths, not <text>: a glyph would depend on the page's font.
  orderedList: [
    { tag: "path", d: "M3.75 4.5 5.25 3.5V8.5", strokeWidth: 1.25 },
    {
      tag: "path",
      d: "M3.6 10.4C3.9 9.8 4.4 9.5 5 9.5 5.8 9.5 6.4 10 6.4 10.8 6.4 11.8 5.5 12.4 3.6 14.5H6.6",
      strokeWidth: 1.25,
    },
    {
      tag: "path",
      d: "M3.75 15.5H6.4L4.9 17.3C5.9 17.2 6.6 17.8 6.6 18.8 6.6 19.8 5.8 20.5 5 20.5 4.4 20.5 3.9 20.2 3.6 19.8",
      strokeWidth: 1.25,
    },
    { tag: "path", d: "M10 6H20M10 12H20M10 18H20" },
  ],
  blockquote: [{ tag: "path", d: "M4 5V19M9 8H20M9 12H20M9 16H16" }],
  // A heading without a level: the essay field has just one (h4).
  heading: [{ tag: "path", d: "M6.5 5V19M17.5 5V19M6.5 12H17.5" }],
};

const SVG_NS = "http://www.w3.org/2000/svg";

// The icon as an <svg> element, for code without React.
export function svgIcon(name, className) {
  const svg = document.createElementNS(SVG_NS, "svg");
  setAttributes(svg, {
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    "stroke-width": "1.5",
    "stroke-linecap": "round",
    "stroke-linejoin": "round",
    "aria-hidden": "true",
  });
  if (className) svg.setAttribute("class", className);

  for (const { tag, strokeWidth, ...attrs } of EDITOR_ICONS[name]) {
    const el = document.createElementNS(SVG_NS, tag);
    setAttributes(el, attrs);
    if (strokeWidth) el.setAttribute("stroke-width", String(strokeWidth));
    svg.appendChild(el);
  }
  return svg;
}

function setAttributes(el, attrs) {
  for (const [key, value] of Object.entries(attrs)) el.setAttribute(key, String(value));
}
