// PowerView keyboard hook for the exam-correction power-view modal.
//
// Attached to the modal element. Manages:
//   * Initial focus on the first row
//   * J/L shortcuts → push "set_block_verdict" (full points / zero) for the
//     focused row (focus stays put; the teacher advances manually with Tab)
//   * K → opens the manual points input ("open_block_manual_input"); the
//     server answers with "focus-manual-input" so the input receives focus.
//     Enter submits the form natively; Escape inside the form cancels it
//     (stopPropagation keeps the modal's window-level Escape from closing).
//   * Tab focus trap inside the modal
//   * Escape closes the modal (delegated to the existing close handler)
//
// The action buttons ("Erledigen" / "Zum nächsten Teilnehmenden") are activated
// natively via Enter — no JS handling needed.
export const PowerView = {
  mounted() {
    this.rows = () => Array.from(this.el.querySelectorAll("[data-power-row]"));

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
          '[data-power-row], input:not([tabindex="-1"]):not([type="hidden"]), button:not([tabindex="-1"]):not([disabled]), [href]:not([tabindex="-1"])',
        ),
      ).filter((el) => !el.disabled);

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

      // Escape inside the manual points form cancels just the form — keep it
      // from bubbling to the window-level handler that closes the modal.
      if (e.key === "Escape") {
        const form =
          document.activeElement &&
          document.activeElement.closest("[data-power-manual-form]");
        if (form) {
          e.preventDefault();
          e.stopPropagation();
          this.pushEvent("cancel_block_manual_input", {});
        }
        return;
      }

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
