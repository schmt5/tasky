// PowerView keyboard hook for the power panel of the exam correction, which
// sits beside the editor on the single correction page.
//
// Attached to the panel element. Manages:
//   * Focus on the first row on mount and whenever the server pushes
//     "power-view-refocus" (next participant or question)
//   * J/L shortcuts → push "set_block_verdict" (full points / zero) for the
//     focused row (focus stays put; the teacher advances manually with Tab)
//   * K → opens the manual points input ("open_block_manual_input"); the
//     server answers with "focus-manual-input" so the input receives focus.
//     Enter submits the form natively; Escape inside the form cancels it.
//
// No focus trap: the panel is part of the page, and Tab may leave it for the
// editor. The action buttons are activated natively via Enter.
export const PowerView = {
  mounted() {
    this.rows = () => Array.from(this.el.querySelectorAll("[data-power-row]"));

    // Defer focus until after LiveView's morphdom settles and the panel is
    // actually painted. A single rAF isn't always enough on first mount.
    const focusFirstRow = () => {
      const rows = this.rows();
      if (rows.length === 0) return;
      rows[0].focus({ preventScroll: false });
    };

    this.focusFirstRow = focusFirstRow;

    setTimeout(focusFirstRow, 0);
    // Retry once more after layout to defeat any focus stealers (e.g. the
    // editor or a sibling button auto-focusing).
    setTimeout(focusFirstRow, 80);

    // Navigating to another participant or question is a push_patch: the
    // panel keeps its DOM id so `mounted()` does NOT re-run. The server pushes
    // "power-view-refocus" from handle_params so the first row of the new
    // answer gets the focus.
    this.handleEvent("power-view-refocus", () => {
      setTimeout(focusFirstRow, 0);
      setTimeout(focusFirstRow, 80);
    });

    // Server-pushed after open_block_manual_input: focus + select the points
    // input once the patched DOM is in place.
    this.handleEvent("focus-manual-input", ({ id }) => {
      const focusInput = () => {
        const input = document.getElementById(id);
        if (input) {
          input.focus({ preventScroll: false });
          input.select();
        }
      };
      setTimeout(focusInput, 0);
      setTimeout(focusInput, 80);
    });

    this.keyHandler = (e) => {
      if (e.defaultPrevented) return;

      // Escape inside the manual points form cancels just the form.
      if (e.key === "Escape") {
        const form =
          document.activeElement &&
          document.activeElement.closest("[data-power-manual-form]");
        if (form) {
          e.preventDefault();
          this.pushEvent("cancel_block_manual_input", {});
        }
        return;
      }

      const active = document.activeElement;

      const onRow = active && active.hasAttribute("data-power-row");
      if (!onRow) return;

      const key = e.key.toLowerCase();
      const index = parseInt(active.dataset.powerRow, 10);

      if (key === "k") {
        e.preventDefault();
        this.pushEvent("open_block_manual_input", { index });
        return;
      }

      const verdictMap = { j: "correct", l: "wrong" };
      const verdict = verdictMap[key];
      if (!verdict) return;

      // Set the verdict for the focused row only. Focus deliberately stays put
      // (no auto-advance) so the teacher controls when to move on.
      e.preventDefault();
      this.pushEvent("set_block_verdict", { index, verdict });
    };

    this.el.addEventListener("keydown", this.keyHandler);
  },

  destroyed() {
    if (this.keyHandler) {
      this.el.removeEventListener("keydown", this.keyHandler);
    }
  },
};
