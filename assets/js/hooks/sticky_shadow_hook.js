// Toggles `is-scrolled` on the element once the page has scrolled past its
// natural top position, so a sticky header/bar can grow a shadow to detach
// cleanly from the content beneath it.
//
// Works regardless of which element scrolls: a 1px sentinel is inserted just
// above the element and observed against the viewport.
export const StickyShadow = {
  mounted() {
    const sentinel = document.createElement("div");
    sentinel.setAttribute("aria-hidden", "true");
    sentinel.style.height = "1px";
    sentinel.style.marginBottom = "-1px";
    sentinel.style.pointerEvents = "none";
    this.el.parentNode.insertBefore(sentinel, this.el);
    this.sentinel = sentinel;

    this.observer = new IntersectionObserver(
      ([entry]) => {
        this.el.classList.toggle("is-scrolled", entry.intersectionRatio === 0);
      },
      { threshold: [0, 1] },
    );
    this.observer.observe(sentinel);
  },

  destroyed() {
    if (this.observer) this.observer.disconnect();
    if (this.sentinel) this.sentinel.remove();
  },
};
