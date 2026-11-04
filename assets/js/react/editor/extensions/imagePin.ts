// Pin images ("Pin auf Bild"): an image on which learners set numbered pins.
// See Tasky.Correction.ImagePin for the data: `attrs.pins` carries the pin
// ids only in the exam content, positions and zones in the sample solution,
// positions in a learner's answer. A pin's number and colour come from its
// place in the list.
//
// The node view has three faces, chosen by the editor's flags:
//   * "author"   — the "Inhalt" tab: the image, and where the pins are set.
//   * "solution" — the "Musterlösung": add, place, drag and size pins.
//   * "view"     — correction, read-only and paper: the pins and, where the
//                  document carries them, the zones of the sample solution
//                  (`attrs.solution`, see Tasky.Correction.SolutionHints).
// Learners never meet this view: they answer in the native answer sheet
// (assets/js/image_pin_field.js).

import { Node } from "@tiptap/core";
import { generateAnswerId } from "../ids";
import { verdictAttribute } from "./answers";
// @ts-ignore — plain JS module shared with the learner's answer sheet.
import { pinColor, zoneBox, placed, MAX_PINS } from "../../../image_pin_colors";

type Zone = { shape: "circle"; r: number } | { shape: "rect"; w: number; h: number };
type Pin = { pinId: string; x?: number | null; y?: number | null; zone?: Zone };

export type ImagePinMode = "author" | "solution" | "view";

const DEFAULT_ZONE: Zone = { shape: "circle", r: 0.05 };

function jsonAttribute(name: string, fallback: unknown) {
  return {
    default: fallback,
    parseHTML: (el: HTMLElement) => {
      try {
        return JSON.parse(el.getAttribute(name) || "null") ?? fallback;
      } catch {
        return fallback;
      }
    },
    renderHTML: () => ({}),
  };
}

export const ImagePin = Node.create({
  name: "imagePin",
  group: "block",
  atom: true,
  draggable: true,
  selectable: true,

  addOptions() {
    return { mode: "view" as ImagePinMode };
  },

  addAttributes() {
    return {
      answerId: {
        default: null,
        parseHTML: (el: HTMLElement) => el.getAttribute("data-answer-id"),
        renderHTML: (attrs: Record<string, unknown>) =>
          attrs.answerId ? { "data-answer-id": attrs.answerId } : {},
      },
      src: {
        default: null,
        parseHTML: (el: HTMLElement) => el.querySelector("img")?.getAttribute("src") ?? null,
        renderHTML: () => ({}),
      },
      alt: {
        default: "",
        parseHTML: (el: HTMLElement) => el.querySelector("img")?.getAttribute("alt") ?? "",
        renderHTML: () => ({}),
      },
      aspect: {
        default: 1,
        parseHTML: (el: HTMLElement) => Number(el.getAttribute("data-aspect")) || 1,
        renderHTML: (attrs: Record<string, unknown>) => ({ "data-aspect": attrs.aspect }),
      },
      pins: {
        ...jsonAttribute("data-pins", []),
        renderHTML: (attrs: Record<string, unknown>) => ({
          "data-pins": JSON.stringify(attrs.pins || []),
        }),
      },
      // Only ever set on a document built for viewing; never saved.
      solution: jsonAttribute("data-solution", null),
      ...verdictAttribute,
    };
  },

  parseHTML() {
    return [{ tag: "div[data-image-pin]" }];
  },

  renderHTML({ node, HTMLAttributes }) {
    return [
      "div",
      { ...HTMLAttributes, "data-image-pin": "" },
      ["img", { src: node.attrs.src, alt: node.attrs.alt }],
    ];
  },

  addCommands() {
    return {
      insertImagePin:
        ({ src, aspect, alt = "" }: { src: string; aspect: number; alt?: string }) =>
        ({ chain }: { chain: any }) =>
          chain()
            .insertContent({
              type: this.name,
              attrs: { answerId: generateAnswerId(), src, aspect, alt, pins: [] },
            })
            .run(),
    } as any;
  },

  addNodeView() {
    const mode = this.options.mode as ImagePinMode;
    return ({ node, getPos, editor }) => new ImagePinView(node, getPos, editor, mode);
  },
});

/** Loads an image file's URL and resolves to its width/height. */
export function measureAspect(src: string): Promise<number> {
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () =>
      resolve(img.naturalWidth && img.naturalHeight ? img.naturalWidth / img.naturalHeight : 1);
    img.onerror = () => resolve(1);
    img.src = src;
  });
}

function newPinId(): string {
  return "p_" + generateAnswerId().replace(/-/g, "").slice(0, 8);
}

const round = (n: number) => Math.round(Math.min(1, Math.max(0, n)) * 10000) / 10000;

class ImagePinView {
  dom: HTMLElement;
  node: any;
  getPos: () => number | undefined;
  editor: any;
  mode: ImagePinMode;
  selected = 0;
  stage!: HTMLElement;
  // The click that ends a drag lands on the image; it must not move a pin.
  dragging = false;

  constructor(node: any, getPos: any, editor: any, mode: ImagePinMode) {
    this.node = node;
    this.getPos = getPos;
    this.editor = editor;
    this.mode = mode;
    this.dom = document.createElement("div");
    this.dom.className = `image-pin image-pin--${mode}`;
    this.dom.contentEditable = "false";
    this.render();
  }

  get pins(): Pin[] {
    return Array.isArray(this.node.attrs.pins) ? this.node.attrs.pins : [];
  }

  get aspect(): number {
    return Number(this.node.attrs.aspect) || 1;
  }

  setPins(pins: Pin[]) {
    const pos = this.getPos();
    if (typeof pos !== "number") return;
    // A placed pin always says how far off still counts.
    pins = pins.map((p) => (placed(p) && !p.zone ? { ...p, zone: DEFAULT_ZONE } : p));
    const tr = this.editor.state.tr.setNodeMarkup(pos, undefined, { ...this.node.attrs, pins });
    this.editor.view.dispatch(tr);
  }

  render() {
    this.dom.replaceChildren();

    this.stage = document.createElement("div");
    this.stage.className = "image-pin__stage";
    const img = document.createElement("img");
    img.src = this.node.attrs.src || "";
    img.alt = this.node.attrs.alt || "";
    img.draggable = false;
    this.stage.appendChild(img);
    this.dom.appendChild(this.stage);

    const solution: Pin[] | null = Array.isArray(this.node.attrs.solution)
      ? this.node.attrs.solution
      : null;

    if (this.mode === "author") {
      const note = document.createElement("p");
      note.className = "image-pin__note";
      const count = this.pins.length;
      note.textContent =
        count === 0
          ? "Pin-Bild · Pins und Zielbereiche setzt du in der Musterlösung."
          : `Pin-Bild · ${count} ${count === 1 ? "Pin" : "Pins"} (in der Musterlösung)`;
      this.dom.appendChild(note);
      return;
    }

    // Zones: the sample solution's — on the sample itself, or hung onto a
    // learner's document for viewing.
    const zonePins = this.mode === "solution" ? this.pins : solution || this.zonedPins();
    zonePins.forEach((pin, i) => {
      if (placed(pin)) this.stage.appendChild(this.zoneEl(pin, i));
    });

    this.pins.forEach((pin, i) => {
      if (placed(pin)) this.stage.appendChild(this.markerEl(pin, i));
    });

    if (this.mode === "solution") {
      this.stage.classList.add("image-pin__stage--placing");
      this.stage.addEventListener("click", (e) => this.placeSelected(e));
      this.renderControls();
    }
  }

  // A sample-solution document carries its zones on its own pins.
  zonedPins(): Pin[] {
    return this.pins.filter((pin) => pin.zone);
  }

  zoneEl(pin: Pin, index: number) {
    const box = zoneBox(pin, this.aspect);
    const el = document.createElement("div");
    el.className = `image-pin__zone image-pin__zone--${box.shape}`;
    el.style.left = `${box.left}%`;
    el.style.top = `${box.top}%`;
    el.style.width = `${box.width}%`;
    el.style.height = `${box.height}%`;
    el.style.setProperty("--pin-color", pinColor(index).bg);
    return el;
  }

  markerEl(pin: Pin, index: number) {
    const { bg, fg } = pinColor(index);
    const el = document.createElement(this.mode === "solution" ? "button" : "span");
    el.className = "image-pin__marker";
    if (this.mode === "solution" && index === this.selected) el.classList.add("is-selected");
    el.style.left = `${(pin.x as number) * 100}%`;
    el.style.top = `${(pin.y as number) * 100}%`;
    el.style.background = bg;
    el.style.color = fg;
    el.textContent = String(index + 1);
    el.setAttribute("aria-label", `Pin ${index + 1}`);

    if (this.mode === "solution") {
      (el as HTMLButtonElement).type = "button";
      el.addEventListener("pointerdown", (e) => this.startDrag(e as PointerEvent, index));
      el.addEventListener("click", (e) => e.stopPropagation());
      el.addEventListener("keydown", (e) => this.nudge(e as KeyboardEvent, index));
    }
    return el;
  }

  renderControls() {
    const bar = document.createElement("div");
    bar.className = "image-pin__controls";

    const chips = document.createElement("div");
    chips.className = "image-pin__chips";
    this.pins.forEach((pin, i) => {
      const { bg, fg } = pinColor(i);
      const chip = document.createElement("button");
      chip.type = "button";
      chip.className = "image-pin__chip";
      if (i === this.selected) chip.classList.add("is-selected");
      chip.style.background = bg;
      chip.style.color = fg;
      chip.textContent = String(i + 1);
      chip.setAttribute("aria-label", `Pin ${i + 1} auswählen`);
      chip.setAttribute("aria-pressed", i === this.selected ? "true" : "false");
      chip.addEventListener("click", () => {
        this.selected = i;
        this.render();
      });
      chips.appendChild(chip);
    });

    if (this.pins.length < MAX_PINS) {
      const add = document.createElement("button");
      add.type = "button";
      add.className = "image-pin__add";
      add.textContent = "+ Pin";
      add.addEventListener("click", () => {
        this.selected = this.pins.length;
        this.setPins([...this.pins, { pinId: newPinId(), x: 0.5, y: 0.5, zone: DEFAULT_ZONE }]);
      });
      chips.appendChild(add);
    }
    bar.appendChild(chips);

    const pin = this.pins[this.selected];
    if (pin) bar.appendChild(this.pinSettings(pin));
    else {
      const hint = document.createElement("p");
      hint.className = "image-pin__note";
      hint.textContent = "Füge einen Pin hinzu und klicke aufs Bild, wo er hingehört.";
      bar.appendChild(hint);
    }

    this.dom.appendChild(bar);
  }

  pinSettings(pin: Pin) {
    const zone = pin.zone || DEFAULT_ZONE;
    const wrap = document.createElement("div");
    wrap.className = "image-pin__settings";

    const shape = document.createElement("div");
    shape.className = "image-pin__segmented";
    shape.setAttribute("role", "radiogroup");
    shape.setAttribute("aria-label", "Form des Zielbereichs");
    for (const [value, label] of [
      ["circle", "Kreis"],
      ["rect", "Rechteck"],
    ] as const) {
      const b = document.createElement("button");
      b.type = "button";
      b.textContent = label;
      b.setAttribute("role", "radio");
      b.setAttribute("aria-checked", zone.shape === value ? "true" : "false");
      b.addEventListener("click", () => {
        if (zone.shape === value) return;
        const size = zone.shape === "circle" ? zone.r * 2 : (zone.w + zone.h) / 2;
        const next: Zone =
          value === "circle"
            ? { shape: "circle", r: round(size / 2) }
            : { shape: "rect", w: round(size), h: round(size * this.aspect) };
        this.updatePin({ ...pin, zone: next });
      });
      shape.appendChild(b);
    }
    wrap.appendChild(shape);

    if (zone.shape === "circle") {
      wrap.appendChild(
        this.slider("Radius", zone.r, 0.01, 0.3, (r) =>
          this.updatePin({ ...pin, zone: { shape: "circle", r } }),
        ),
      );
    } else {
      wrap.appendChild(
        this.slider("Breite", zone.w, 0.02, 0.8, (w) =>
          this.updatePin({ ...pin, zone: { ...zone, w } }),
        ),
      );
      wrap.appendChild(
        this.slider("Höhe", zone.h, 0.02, 0.8, (h) =>
          this.updatePin({ ...pin, zone: { ...zone, h } }),
        ),
      );
    }

    const remove = document.createElement("button");
    remove.type = "button";
    remove.className = "image-pin__remove";
    remove.textContent = "Pin entfernen";
    remove.addEventListener("click", () => {
      const pins = this.pins.filter((p) => p.pinId !== pin.pinId);
      this.selected = Math.max(0, Math.min(this.selected, pins.length - 1));
      this.setPins(pins);
    });
    wrap.appendChild(remove);

    return wrap;
  }

  slider(label: string, value: number, min: number, max: number, onChange: (v: number) => void) {
    const wrap = document.createElement("label");
    wrap.className = "image-pin__slider";
    const text = document.createElement("span");
    text.textContent = label;
    const input = document.createElement("input");
    input.type = "range";
    input.min = String(min);
    input.max = String(max);
    input.step = "0.005";
    input.value = String(value);
    // Applied on release: one document change per gesture, not one per pixel.
    input.addEventListener("change", () => onChange(round(Number(input.value))));
    wrap.append(text, input);
    return wrap;
  }

  updatePin(pin: Pin) {
    this.setPins(this.pins.map((p) => (p.pinId === pin.pinId ? pin : p)));
  }

  relative(e: { clientX: number; clientY: number }) {
    const rect = this.stage.getBoundingClientRect();
    return {
      x: round((e.clientX - rect.left) / rect.width),
      y: round((e.clientY - rect.top) / rect.height),
    };
  }

  placeSelected(e: MouseEvent) {
    if (this.dragging) return;
    const pin = this.pins[this.selected];
    if (!pin) return;
    this.updatePin({ ...pin, ...this.relative(e) });
  }

  startDrag(e: PointerEvent, index: number) {
    e.preventDefault();
    e.stopPropagation();
    this.selected = index;
    const marker = e.currentTarget as HTMLElement;
    marker.setPointerCapture(e.pointerId);
    this.dragging = true;
    let last = { x: this.pins[index].x as number, y: this.pins[index].y as number };

    const move = (ev: PointerEvent) => {
      last = this.relative(ev);
      marker.style.left = `${last.x * 100}%`;
      marker.style.top = `${last.y * 100}%`;
    };
    const up = () => {
      marker.removeEventListener("pointermove", move);
      marker.removeEventListener("pointerup", up);
      marker.removeEventListener("pointercancel", up);
      setTimeout(() => (this.dragging = false));
      this.updatePin({ ...this.pins[index], ...last });
    };
    marker.addEventListener("pointermove", move);
    marker.addEventListener("pointerup", up);
    marker.addEventListener("pointercancel", up);
  }

  nudge(e: KeyboardEvent, index: number) {
    const step = e.shiftKey ? 0.05 : 0.01;
    const d: Record<string, [number, number]> = {
      ArrowLeft: [-step, 0],
      ArrowRight: [step, 0],
      ArrowUp: [0, -step],
      ArrowDown: [0, step],
    };
    const delta = d[e.key];
    if (!delta) return;
    e.preventDefault();
    const pin = this.pins[index];
    this.selected = index;
    this.updatePin({
      ...pin,
      x: round((pin.x as number) + delta[0]),
      y: round((pin.y as number) + delta[1]),
    });
    queueMicrotask(() =>
      (this.dom.querySelectorAll(".image-pin__marker")[index] as HTMLElement | undefined)?.focus(),
    );
  }

  update(node: any) {
    if (node.type !== this.node.type) return false;
    this.node = node;
    this.render();
    return true;
  }

  stopEvent(event: Event) {
    // Clicks, keys and drags on the controls belong to the view, not to
    // ProseMirror — except in the content editor, where the node is moved.
    return this.mode === "solution" && !event.type.startsWith("drag");
  }

  ignoreMutation() {
    return true;
  }
}
