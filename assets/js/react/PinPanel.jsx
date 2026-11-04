import { useEffect, useReducer, useSyncExternalStore } from "react";
import * as solutionStore from "./solutionEditorStore";
import * as pinSelection from "./editor/pinSelection";
import {
  listPinImages,
  setImagePins,
  newPinId,
  round,
  DEFAULT_ZONE,
} from "./editor/extensions/imagePin";
import { pinColor, MAX_PINS } from "../image_pin_colors";

// The "Pins" section of a question's card in the Musterlösung: add, pick,
// size and remove the pins of the question's pin image. Placing and dragging
// them stays on the image (extensions/imagePin.ts); both share the picked pin
// through ./editor/pinSelection. Every change goes straight into the part's
// editor as a transaction, so its autosave and undo cover it.
export default function PinPanel({ partId }) {
  useSyncExternalStore(solutionStore.subscribe, solutionStore.getSnapshot);
  const editor = solutionStore.getEditor(partId);
  useSyncExternalStore(pinSelection.subscribe, pinSelection.getVersion);
  useEditorTransactions(editor);

  if (!editor || editor.isDestroyed) return null;

  const images = listPinImages(editor.state.doc);
  if (images.length === 0) return null;

  const activeId = pinSelection.activeImage(editor);
  const image = images.find((i) => i.answerId === activeId) || images[0];
  const imageNo = images.indexOf(image) + 1;
  const { pins } = image;
  const selected = Math.min(pinSelection.selectedIndex(editor, image.answerId), pins.length - 1);
  const pin = pins[selected];

  const pick = (index) => pinSelection.select(editor, image.answerId, index);
  const write = (next) => setImagePins(editor, image.answerId, next);
  const updatePin = (next) => write(pins.map((p) => (p.pinId === next.pinId ? next : p)));

  return (
    <section id={`pin-panel-${partId}`} aria-label="Pins">
      <div className="flex items-baseline justify-between gap-2 mb-3">
        <h3 className="text-xs font-semibold text-stone-500 uppercase tracking-wide">Pins</h3>
        {images.length > 1 && (
          <span className="text-xs text-stone-400">
            Pin-Bild {imageNo} von {images.length}
          </span>
        )}
      </div>

      {images.length > 1 && (
        <div className="image-pin__segmented w-full mb-3" role="radiogroup" aria-label="Pin-Bild">
          {images.map((img, i) => (
            <button
              key={img.answerId}
              type="button"
              role="radio"
              aria-checked={img === image}
              className="flex-1"
              onClick={() => pinSelection.select(editor, img.answerId, 0)}
            >
              Bild {i + 1}
            </button>
          ))}
        </div>
      )}

      <div className="image-pin__chips">
        {pins.map((p, i) => {
          const { bg, fg } = pinColor(i);
          return (
            <button
              key={p.pinId}
              type="button"
              className={"image-pin__chip" + (i === selected ? " is-selected" : "")}
              style={{ background: bg, color: fg }}
              aria-label={`Pin ${i + 1} auswählen`}
              aria-pressed={i === selected}
              onClick={() => pick(i)}
            >
              {i + 1}
            </button>
          );
        })}
        {pins.length < MAX_PINS && (
          <button
            type="button"
            className="image-pin__add"
            onClick={() => {
              pick(pins.length);
              write([...pins, { pinId: newPinId(), x: 0.5, y: 0.5, zone: DEFAULT_ZONE }]);
            }}
          >
            + Pin
          </button>
        )}
      </div>

      {pin ? (
        <PinSettings
          key={pin.pinId}
          pin={pin}
          aspect={image.aspect}
          onChange={updatePin}
          onRemove={() => {
            pick(Math.max(0, selected - 1));
            write(pins.filter((p) => p.pinId !== pin.pinId));
          }}
        />
      ) : (
        <p className="mt-3 text-xs text-stone-500 leading-relaxed">
          Füge einen Pin hinzu und klicke links aufs Bild, wo er hingehört.
        </p>
      )}
    </section>
  );
}

function PinSettings({ pin, aspect, onChange, onRemove }) {
  const zone = pin.zone || DEFAULT_ZONE;

  const setShape = (shape) => {
    if (zone.shape === shape) return;
    const size = zone.shape === "circle" ? zone.r * 2 : (zone.w + zone.h) / 2;
    onChange({
      ...pin,
      zone:
        shape === "circle"
          ? { shape: "circle", r: round(size / 2) }
          : { shape: "rect", w: round(size), h: round(size * aspect) },
    });
  };

  return (
    <div className="mt-4 pt-4 border-t border-stone-100 space-y-3">
      <p className="text-xs text-stone-500">Zielbereich</p>
      <div className="image-pin__segmented w-full" role="radiogroup" aria-label="Form des Zielbereichs">
        {[
          ["circle", "Kreis"],
          ["rect", "Rechteck"],
        ].map(([value, label]) => (
          <button
            key={value}
            type="button"
            role="radio"
            aria-checked={zone.shape === value}
            className="flex-1"
            onClick={() => setShape(value)}
          >
            {label}
          </button>
        ))}
      </div>

      {zone.shape === "circle" ? (
        <Slider
          label="Radius"
          value={zone.r}
          min={0.01}
          max={0.3}
          onChange={(r) => onChange({ ...pin, zone: { shape: "circle", r } })}
        />
      ) : (
        <>
          <Slider
            label="Breite"
            value={zone.w}
            min={0.02}
            max={0.8}
            onChange={(w) => onChange({ ...pin, zone: { ...zone, w } })}
          />
          <Slider
            label="Höhe"
            value={zone.h}
            min={0.02}
            max={0.8}
            onChange={(h) => onChange({ ...pin, zone: { ...zone, h } })}
          />
        </>
      )}

      <button type="button" className="image-pin__remove" onClick={onRemove}>
        Pin entfernen
      </button>
    </div>
  );
}

// Uncontrolled while dragging, applied on release: one document change per
// gesture, not one per pixel.
function Slider({ label, value, min, max, onChange }) {
  return (
    <label className="flex flex-col gap-1 text-xs text-stone-600">
      <span>{label}</span>
      <input
        key={value}
        type="range"
        min={min}
        max={max}
        step="0.005"
        defaultValue={value}
        className="w-full accent-sky-600"
        onPointerUp={(e) => onChange(round(Number(e.currentTarget.value)))}
        onKeyUp={(e) => onChange(round(Number(e.currentTarget.value)))}
      />
    </label>
  );
}

// Re-renders on every transaction of the part's editor: the pins can also
// change on the image, by undo, or by a save that reloads the document.
function useEditorTransactions(editor) {
  const [, bump] = useReducer((n) => n + 1, 0);
  useEffect(() => {
    if (!editor) return undefined;
    editor.on("transaction", bump);
    return () => editor.off("transaction", bump);
  }, [editor]);
}
