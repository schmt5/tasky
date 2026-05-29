// BulkPowerKeys — inline keyboard navigation for the bulk-correction view.
//
// Attached to the content wrapper that contains both the answer-group cards
// and the "Als erledigt markieren" / "Erledigt zurücknehmen" action button.
//
//   * Focuses the first visible [data-bulk-power-row] on mount.
//   * J/K/L on a focused row → push "set_group_verdict" with that card's
//     {block index, group text} payload, then advance focus to the next
//     visible row. After the last row, focus jumps to the action button,
//     where Enter activates it via the browser default (no JS needed).
//
// Sibling to PowerView (assets/js/hooks/power_view_hook.js), but trimmed:
// no focus trap (this is a full page, not a modal) and no refocus event
// (cross-part navigation uses live_navigate, so the hook fully remounts).
export const BulkPowerKeys = {
  mounted() {
    this.visibleRows = () =>
      Array.from(this.el.querySelectorAll("[data-bulk-power-row]")).filter(
        (el) => el.offsetParent !== null,
      );

    this.toggleBtn = () => this.el.querySelector("[data-bulk-power-toggle]");

    const focusFirst = () => {
      const rows = this.visibleRows();
      if (rows.length === 0) {
        const tgl = this.toggleBtn();
        if (tgl) tgl.focus({ preventScroll: false });
        return;
      }
      rows[0].focus({ preventScroll: false });
    };

    // Belt-and-braces — same pattern as PowerView. The first call settles
    // before layout; the second defeats any focus-stealers that fired late.
    setTimeout(focusFirst, 0);
    setTimeout(focusFirst, 80);

    this.keyHandler = (e) => {
      if (e.defaultPrevented) return;
      const active = document.activeElement;

      // J / K / L only when an answer-group card is focused. Use .closest()
      // so an inner element receiving focus still resolves to its row.
      const row = active && active.closest("[data-bulk-power-row]");
      if (!row) return;

      const map = { j: "correct", k: "half", l: "wrong" };
      const verdict = map[e.key.toLowerCase()];
      if (!verdict) return;
      e.preventDefault();

      const index = row.dataset.blockIndex;
      const text = row.dataset.groupText || "";
      this.pushEvent("set_group_verdict", { index, text, verdict });
      // Stay on the same card — the teacher moves on with Tab when ready.
    };

    this.el.addEventListener("keydown", this.keyHandler);
  },

  destroyed() {
    if (this.keyHandler) {
      this.el.removeEventListener("keydown", this.keyHandler);
    }
  },
};
