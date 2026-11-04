import { pinColor, placed } from "./image_pin_colors";

// The learner's pin image ("Pin auf Bild"): the server renders the image with
// the pins already set (TaskyWeb.ExamDocHTML); this turns it into a field.
// The pins to set are in `data-value` — ids only, plus where the learner put
// them; where they belong never reaches the page.
//
// Pick a pin in the tray, then click or tap the image to set it; drag a set
// pin to move it. From the keyboard: Enter on a tray pin sets it in the
// middle and focuses it, the arrow keys move it (Shift: further), Delete
// takes it back to the tray.
//
// The ExamAnswersForm hook owns saving, as for the essay field: it mounts
// this, reads `value()` and listens for the `input` event.

const round = (n) => Math.round(Math.min(1, Math.max(0, n)) * 10000) / 10000;

export function mountImagePinField(container) {
  const disabled = "disabled" in container.dataset;
  const stage = container.querySelector(".exam-doc__pin-stage");
  if (!stage) return { value: () => [], destroy() {} };

  let pins;
  try {
    pins = JSON.parse(container.dataset.value || "[]").map((p) => ({
      pinId: p.pinId,
      x: typeof p.x === "number" ? p.x : null,
      y: typeof p.y === "number" ? p.y : null,
    }));
  } catch {
    pins = [];
  }

  // The click that ends a drag lands on the image; it must not set a pin.
  let dragging = false;

  let selected = pins.findIndex((p) => !placed(p));
  if (selected < 0) selected = 0;

  const tray = document.createElement("div");
  tray.className = "exam-doc__pin-tray";
  tray.setAttribute("role", "toolbar");
  tray.setAttribute("aria-label", "Pins");

  const status = document.createElement("p");
  status.className = "exam-doc__pin-status";
  status.setAttribute("aria-live", "polite");

  if (!disabled) container.append(tray, status);

  function changed(message) {
    render();
    if (message) status.textContent = message;
    container.dispatchEvent(new Event("input", { bubbles: true }));
  }

  function relative(e) {
    const rect = stage.getBoundingClientRect();
    return {
      x: round((e.clientX - rect.left) / rect.width),
      y: round((e.clientY - rect.top) / rect.height),
    };
  }

  function nextUnplaced(from) {
    for (let i = 1; i <= pins.length; i++) {
      const j = (from + i) % pins.length;
      if (!placed(pins[j])) return j;
    }
    return from;
  }

  function place(index, at, focus = false) {
    pins[index] = { ...pins[index], ...at };
    const message = `Pin ${index + 1} gesetzt`;
    selected = nextUnplaced(index);
    changed(message);
    if (focus) markerAt(index)?.focus();
  }

  function remove(index) {
    pins[index] = { ...pins[index], x: null, y: null };
    selected = index;
    changed(`Pin ${index + 1} entfernt`);
    tray.children[index]?.focus();
  }

  function markerAt(index) {
    return stage.querySelector(`[data-pin-index="${index}"]`);
  }

  function render() {
    stage.querySelectorAll(".exam-doc__pin-marker").forEach((m) => m.remove());

    pins.forEach((pin, i) => {
      if (!placed(pin)) return;
      const { bg, fg } = pinColor(i);
      const marker = document.createElement(disabled ? "span" : "button");
      marker.className = "exam-doc__pin-marker";
      marker.dataset.pinIndex = String(i);
      marker.textContent = String(i + 1);
      marker.style.left = `${pin.x * 100}%`;
      marker.style.top = `${pin.y * 100}%`;
      marker.style.background = bg;
      marker.style.color = fg;
      marker.setAttribute(
        "aria-label",
        `Pin ${i + 1}: ${Math.round(pin.x * 100)} % von links, ${Math.round(pin.y * 100)} % von oben`,
      );
      if (!disabled) {
        marker.type = "button";
        marker.addEventListener("pointerdown", (e) => startDrag(e, i));
        marker.addEventListener("click", (e) => e.stopPropagation());
        marker.addEventListener("keydown", (e) => onMarkerKey(e, i));
      }
      stage.appendChild(marker);
    });

    if (disabled) return;

    tray.replaceChildren(
      ...pins.map((pin, i) => {
        const { bg, fg } = pinColor(i);
        const chip = document.createElement("button");
        chip.type = "button";
        chip.className = "exam-doc__pin-chip";
        chip.textContent = String(i + 1);
        chip.style.background = bg;
        chip.style.color = fg;
        chip.dataset.placed = placed(pin) ? "true" : "false";
        chip.setAttribute("aria-pressed", i === selected ? "true" : "false");
        chip.setAttribute(
          "aria-label",
          `Pin ${i + 1}${placed(pin) ? " (gesetzt)" : ""} auswählen`,
        );
        chip.addEventListener("click", (e) => {
          selected = i;
          // Activated from the keyboard (no pointer position): set the pin in
          // the middle, ready for the arrow keys.
          if (e.detail === 0 && !placed(pin)) {
            place(i, { x: 0.5, y: 0.5 }, true);
          } else {
            render();
            status.textContent = placed(pin)
              ? `Pin ${i + 1} gewählt — tippe aufs Bild, um ihn zu versetzen`
              : `Pin ${i + 1} gewählt — tippe aufs Bild, um ihn zu setzen`;
          }
        });
        return chip;
      }),
    );

    if (!status.textContent) {
      status.textContent = pins.length
        ? `Wähle einen Pin und tippe aufs Bild.`
        : "";
    }
  }

  function onStageClick(e) {
    if (disabled || dragging || pins.length === 0) return;
    place(selected, relative(e));
  }

  function startDrag(e, index) {
    e.preventDefault();
    const marker = e.currentTarget;
    marker.setPointerCapture(e.pointerId);
    dragging = true;
    let last = null;
    const move = (ev) => {
      last = relative(ev);
      marker.style.left = `${last.x * 100}%`;
      marker.style.top = `${last.y * 100}%`;
    };
    const up = () => {
      marker.removeEventListener("pointermove", move);
      marker.removeEventListener("pointerup", up);
      marker.removeEventListener("pointercancel", up);
      setTimeout(() => (dragging = false));
      selected = index;
      if (last) {
        pins[index] = { ...pins[index], ...last };
        changed(`Pin ${index + 1} versetzt`);
      } else {
        render();
      }
      markerAt(index)?.focus();
    };
    marker.addEventListener("pointermove", move);
    marker.addEventListener("pointerup", up);
    marker.addEventListener("pointercancel", up);
  }

  function onMarkerKey(e, index) {
    if (e.key === "Delete" || e.key === "Backspace") {
      e.preventDefault();
      remove(index);
      return;
    }
    const step = e.shiftKey ? 0.05 : 0.01;
    const delta = {
      ArrowLeft: [-step, 0],
      ArrowRight: [step, 0],
      ArrowUp: [0, -step],
      ArrowDown: [0, step],
    }[e.key];
    if (!delta) return;
    e.preventDefault();
    const pin = pins[index];
    pins[index] = { ...pin, x: round(pin.x + delta[0]), y: round(pin.y + delta[1]) };
    selected = index;
    changed();
    markerAt(index)?.focus();
  }

  if (!disabled) {
    stage.classList.add("exam-doc__pin-stage--active");
    stage.addEventListener("click", onStageClick);
  }
  render();

  return {
    value: () => pins.map((p) => ({ ...p })),
    destroy: () => stage.removeEventListener("click", onStageClick),
  };
}
