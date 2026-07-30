// Stable ids for answer-bearing nodes and question headings. Generated
// client-side so ids never change across saves; the server only assigns
// fallbacks for legacy docs.

export function generateAnswerId(): string {
  if (window.crypto?.randomUUID) return window.crypto.randomUUID();
  // Non-secure-context fallback (crypto.randomUUID needs https/localhost).
  const bytes = new Uint8Array(16);
  window.crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

export function generatePartId(): string {
  return "q-" + generateAnswerId().replace(/-/g, "").slice(0, 8);
}
