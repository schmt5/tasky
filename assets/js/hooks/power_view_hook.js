// PowerView keyboard hook for the exam-correction power-view modal.
//
// Attached to the modal element. Manages:
//   * Initial focus on the first row
//   * J/K/L shortcuts → push "set_block_verdict" then advance focus
//   * After the last row, focus jumps to the "toggle corrected" button
//   * Spacebar on "toggle corrected" → toggles + moves focus to "next submission"
//   * Spacebar on "next submission" → navigates to next
//   * Escape closes the modal (delegated to the existing close handler)
export const PowerView = {
  mounted() {
    this.rows = () => Array.from(this.el.querySelectorAll("[data-power-row]"));
    this.toggleCorrected = () =>
      this.el.querySelector("[data-power-toggle-corrected]");
    this.nextSubmission = () =>
      this.el.querySelector("[data-power-next-submission]");

    // Defer focus until after LiveView's morphdom settles and the dialog is
    // actually painted. A single rAF isn't always enough on first mount.
    const focusFirstRow = () => {
      const rows = this.rows();
      if (rows.length === 0) return;
      rows[0].focus({ preventScroll: false });
    };

    this.focusFirstRow = focusFirstRow;

    setTimeout(focusFirstRow, 0);
    // Retry once more after layout to defeat any focus stealers (e.g. the
    // dialog element or a sibling button auto-focusing).
    setTimeout(focusFirstRow, 80);

    // When navigating to the next submission via push_patch, the modal
    // container keeps its DOM id so `mounted()` does NOT re-run. The server
    // pushes "power-view-refocus" after the patch so we can re-focus the
    // first row of the (now different) submission.
    this.handleEvent("power-view-refocus", () => {
      setTimeout(focusFirstRow, 0);
      setTimeout(focusFirstRow, 80);
    });

    this.focusables = () =>
      Array.from(
        this.el.querySelectorAll(
          '[data-power-row], button:not([tabindex="-1"]):not([disabled]), [href]:not([tabindex="-1"])',
        ),
      ).filter((el) => !el.disabled);

    this.keyHandler = (e) => {
      if (e.defaultPrevented) return;

      // Focus trap: keep Tab navigation inside the modal.
      if (e.key === "Tab") {
        const items = this.focusables();
        if (items.length === 0) return;
        const first = items[0];
        const last = items[items.length - 1];
        const active = document.activeElement;

        if (e.shiftKey && active === first) {
          e.preventDefault();
          last.focus();
          return;
        }
        if (!e.shiftKey && active === last) {
          e.preventDefault();
          first.focus();
          return;
        }
        // If focus has somehow escaped the modal entirely, pull it back.
        if (!this.el.contains(active)) {
          e.preventDefault();
          first.focus();
          return;
        }
        return;
      }

      const active = document.activeElement;

      // Spacebar handling for the action buttons
      if (e.key === " " || e.key === "Spacebar") {
        const toggle = this.toggleCorrected();
        const next = this.nextSubmission();

        if (active === toggle) {
          e.preventDefault();
          toggle.click();
          // Move focus to "next submission" button after toggling
          if (next && !next.disabled) {
            setTimeout(() => next.focus(), 50);
          }
          return;
        }

        if (active === next && !next.disabled) {
          e.preventDefault();
          next.click();
          return;
        }
      }

      const onRow = active && active.hasAttribute("data-power-row");
      if (!onRow) return;

      const key = e.key.toLowerCase();
      const verdictMap = { j: "correct", k: "half", l: "wrong" };
      const verdict = verdictMap[key];
      if (!verdict) return;

      e.preventDefault();
      const index = parseInt(active.dataset.powerRow, 10);
      this.pushEvent("set_block_verdict", { index, verdict });

      // Advance focus: next row, or "toggle corrected" button if last row.
      const rows = this.rows();
      const nextRow = rows[index + 1];
      if (nextRow) {
        nextRow.focus();
      } else {
        const toggle = this.toggleCorrected();
        if (toggle) toggle.focus();
      }
    };

    this.el.addEventListener("keydown", this.keyHandler);
  },

  destroyed() {
    if (this.keyHandler) {
      this.el.removeEventListener("keydown", this.keyHandler);
    }
  },
};
