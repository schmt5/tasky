// The colours of pin 1, 2, 3, … on a pin image (Okabe-Ito, distinguishable
// with colour blindness), each with the colour of the number on it. The same
// list is Tasky.Correction.ImagePin.colors/0 and `pin-colors` in
// priv/typst/tiptap.typ. The number is always shown: colour alone would fail
// colour-blind readers and black-and-white print.
export const PIN_COLORS = [
  { bg: "#E69F00", fg: "#1C1917" },
  { bg: "#56B4E9", fg: "#1C1917" },
  { bg: "#009E73", fg: "#FFFFFF" },
  { bg: "#F0E442", fg: "#1C1917" },
  { bg: "#0072B2", fg: "#FFFFFF" },
  { bg: "#D55E00", fg: "#FFFFFF" },
  { bg: "#CC79A7", fg: "#1C1917" },
  { bg: "#1C1917", fg: "#FFFFFF" },
];

export const MAX_PINS = PIN_COLORS.length;

export function pinColor(index) {
  return PIN_COLORS[index % PIN_COLORS.length];
}

// Where a zone sits on the image, in percent of its width and height. A
// circle's radius is relative to the width; its height is the same length in
// height units (r × width/height), so it stays round on any image.
export function zoneBox(pin, aspect) {
  const zone = pin.zone || { shape: "circle", r: 0.05 };
  if (zone.shape === "rect") {
    return {
      shape: "rect",
      left: (pin.x - zone.w / 2) * 100,
      top: (pin.y - zone.h / 2) * 100,
      width: zone.w * 100,
      height: zone.h * 100,
    };
  }
  const ry = zone.r * (aspect || 1);
  return {
    shape: "circle",
    left: (pin.x - zone.r) * 100,
    top: (pin.y - ry) * 100,
    width: zone.r * 200,
    height: ry * 200,
  };
}

export function placed(pin) {
  return pin && typeof pin.x === "number" && typeof pin.y === "number";
}
