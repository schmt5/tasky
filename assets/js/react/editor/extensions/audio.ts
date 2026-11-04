// Audio blocks: a sound file learners listen to, at most `maxPlays` times
// (null: as often as they like). See Tasky.AudioPlays for how plays are
// counted — always on the server, from this node's attrs in the exam's or
// unit's own content.
//
// The node view is the player (assets/js/audio_player.js) and, while
// authoring, the block's settings below it. Learners on the native answer
// sheet get the same player from ExamAnswersForm; in a free-document exam
// they meet this node view, configured with their `learner` routes.

import { Node } from "@tiptap/core";
import { generateAnswerId } from "../ids";
// @ts-ignore — plain JS module shared with the learner's answer sheet.
import { mountAudioPlayer } from "../../../audio_player";

export type AudioLearner = {
  api: string;
  file: string;
  plays: Record<string, { started: number; active: boolean; position: number }>;
};

export const MAX_PLAYS_CHOICES = [1, 2, 3, 4, 5];

/** `/uploads/exams/1/x.mp3` → `/exams/1/audio/x.mp3` (TaskyWeb.AudioController). */
export function teacherAudioUrl(src: unknown): string | null {
  if (typeof src !== "string") return null;
  const match = src.match(/^\/uploads\/(exams|tasks)\/(\d+)\/([^/]+)$/);
  return match ? `/${match[1]}/${match[2]}/audio/${match[3]}` : null;
}

export const Audio = Node.create({
  name: "audio",
  group: "block",
  atom: true,
  draggable: true,
  selectable: true,

  addOptions() {
    return { authoring: false, learner: null as AudioLearner | null };
  },

  addAttributes() {
    return {
      audioId: {
        default: null,
        parseHTML: (el: HTMLElement) => el.getAttribute("data-audio-id"),
        renderHTML: (attrs: Record<string, unknown>) =>
          attrs.audioId ? { "data-audio-id": attrs.audioId } : {},
      },
      src: {
        default: null,
        parseHTML: (el: HTMLElement) => el.getAttribute("data-src"),
        renderHTML: (attrs: Record<string, unknown>) =>
          attrs.src ? { "data-src": attrs.src } : {},
      },
      title: {
        default: "",
        parseHTML: (el: HTMLElement) => el.getAttribute("data-title") || "",
        renderHTML: (attrs: Record<string, unknown>) =>
          attrs.title ? { "data-title": attrs.title } : {},
      },
      maxPlays: {
        default: null,
        parseHTML: (el: HTMLElement) => Number(el.getAttribute("data-max-plays")) || null,
        renderHTML: (attrs: Record<string, unknown>) =>
          attrs.maxPlays ? { "data-max-plays": attrs.maxPlays } : {},
      },
    };
  },

  parseHTML() {
    return [{ tag: "div[data-audio]" }];
  },

  renderHTML({ HTMLAttributes }) {
    return ["div", { ...HTMLAttributes, "data-audio": "" }];
  },

  addCommands() {
    return {
      insertAudio:
        ({ src, title = "" }: { src: string; title?: string }) =>
        ({ chain }: { chain: any }) =>
          chain()
            .insertContent({
              type: this.name,
              attrs: { audioId: generateAnswerId(), src, title, maxPlays: null },
            })
            .run(),
    } as any;
  },

  addNodeView() {
    const { authoring, learner } = this.options;
    return ({ node, getPos, editor }) =>
      new AudioView(node, getPos as () => number | undefined, editor, authoring, learner);
  },
});

const limitLabel = (max: unknown) => (max ? `höchstens ${max}×` : "beliebig oft");

class AudioView {
  dom: HTMLElement;
  node: any;
  getPos: () => number | undefined;
  editor: any;
  learner: AudioLearner | null;
  playerEl: HTMLElement;
  player: { destroy(): void } | null = null;
  // Authoring only: the pill with the limit, and the menu it opens.
  pill: HTMLButtonElement | null = null;
  menu: HTMLElement | null = null;
  titleInput: HTMLInputElement | null = null;
  radios: HTMLInputElement[] = [];
  onOutside = (e: Event) => {
    if (!this.dom.contains(e.target as globalThis.Node)) this.closeMenu();
  };

  constructor(
    node: any,
    getPos: () => number | undefined,
    editor: any,
    authoring: boolean,
    learner: AudioLearner | null,
  ) {
    this.node = node;
    this.getPos = getPos;
    this.editor = editor;
    this.learner = learner;

    this.dom = document.createElement("div");
    this.dom.className = "exam-doc__audio exam-editor__audio";
    this.dom.setAttribute("data-audio", "");
    this.dom.contentEditable = "false";

    this.playerEl = document.createElement("div");
    this.dom.append(this.playerEl);
    if (authoring) {
      this.dom.classList.add("exam-editor__audio--authoring");
      this.dom.append(...this.settings());
    }
    this.mountPlayer();
  }

  // The settings sit behind a pill showing the limit, in a small menu that
  // hangs off it — no dialog: two values, applied as they change.
  settings(): HTMLElement[] {
    const pill = document.createElement("button");
    pill.type = "button";
    pill.className = "exam-editor__audio-pill";
    pill.setAttribute("aria-haspopup", "true");
    pill.setAttribute("aria-expanded", "false");
    pill.addEventListener("click", () => (this.menu?.hidden ? this.openMenu() : this.closeMenu()));
    this.pill = pill;

    const menu = document.createElement("div");
    menu.className = "exam-editor__audio-menu";
    menu.hidden = true;
    menu.setAttribute("role", "dialog");
    menu.setAttribute("aria-label", "Audio-Einstellungen");
    menu.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        e.preventDefault();
        this.closeMenu();
        pill.focus();
      }
    });

    const titleLabel = document.createElement("label");
    titleLabel.className = "exam-editor__audio-field";
    titleLabel.append("Titel");
    const title = document.createElement("input");
    title.type = "text";
    title.maxLength = 120;
    title.placeholder = "z. B. Hörtext 1";
    // Applied on change (blur, Enter), not per keystroke.
    title.addEventListener("change", () => this.setAttrs({ title: title.value.trim() }));
    title.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        title.blur();
      }
    });
    titleLabel.append(title);
    this.titleInput = title;

    const plays = document.createElement("fieldset");
    plays.className = "exam-editor__audio-plays";
    const legend = document.createElement("legend");
    legend.textContent = "Abspielen";
    plays.append(legend);
    const name = `audio-max-${Math.random().toString(36).slice(2)}`;
    this.radios = [null, ...MAX_PLAYS_CHOICES].map((n) => {
      const label = document.createElement("label");
      label.className = "exam-editor__audio-choice";
      const radio = document.createElement("input");
      radio.type = "radio";
      radio.name = name;
      radio.value = n ? String(n) : "";
      radio.addEventListener("change", () => this.setAttrs({ maxPlays: n }));
      label.append(radio, limitLabel(n));
      plays.append(label);
      return radio;
    });

    const hint = document.createElement("p");
    hint.className = "exam-editor__audio-hint";
    hint.textContent =
      "Mit Limite zählt jeder Start als Durchgang. Lernende können pausieren, aber nicht spulen.";

    menu.append(titleLabel, plays, hint);
    this.menu = menu;
    this.syncSettings();
    return [pill, menu];
  }

  syncSettings() {
    const { title, maxPlays } = this.node.attrs;
    if (this.pill) {
      this.pill.replaceChildren(gearIcon(), document.createTextNode(limitLabel(maxPlays)));
      this.pill.setAttribute("aria-label", `Audio-Einstellungen: ${limitLabel(maxPlays)}`);
    }
    if (this.titleInput && document.activeElement !== this.titleInput) {
      this.titleInput.value = title || "";
    }
    this.radios.forEach((r) => (r.checked = r.value === (maxPlays ? String(maxPlays) : "")));
  }

  openMenu() {
    if (!this.menu || !this.pill) return;
    this.menu.hidden = false;
    this.pill.setAttribute("aria-expanded", "true");
    document.addEventListener("pointerdown", this.onOutside, true);
    this.titleInput?.focus();
  }

  closeMenu() {
    if (!this.menu || this.menu.hidden) return;
    // A title still being typed is kept, as on blur.
    if (this.titleInput && document.activeElement === this.titleInput) this.titleInput.blur();
    this.menu.hidden = true;
    this.pill?.setAttribute("aria-expanded", "false");
    document.removeEventListener("pointerdown", this.onOutside, true);
  }

  setAttrs(patch: Record<string, unknown>) {
    const pos = this.getPos();
    if (typeof pos !== "number") return;
    this.editor.view.dispatch(
      this.editor.view.state.tr.setNodeMarkup(pos, undefined, { ...this.node.attrs, ...patch }),
    );
  }

  mountPlayer() {
    this.player?.destroy();
    const { audioId, src, title, maxPlays } = this.node.attrs;
    const learner = this.learner;
    this.player = mountAudioPlayer(this.playerEl, {
      audioId,
      title,
      maxPlays,
      state: learner?.plays?.[audioId],
      fileUrl: learner ? `${learner.file}/${encodeURIComponent(audioId)}` : teacherAudioUrl(src),
      api: learner?.api ?? null,
      disabled: !this.editor.isEditable && !learner,
    });
  }

  update(node: any) {
    if (node.type !== this.node.type) return false;
    const before = this.node.attrs;
    this.node = node;
    this.syncSettings();
    if (
      before.src !== node.attrs.src ||
      before.title !== node.attrs.title ||
      before.maxPlays !== node.attrs.maxPlays
    ) {
      this.mountPlayer();
    }
    return true;
  }

  // The controls and the menu handle their own events; a click anywhere else
  // selects the block, so it can be moved or deleted.
  stopEvent(event: Event) {
    const target = event.target as HTMLElement | null;
    return Boolean(target?.closest?.("button, input, select, label, .exam-editor__audio-menu"));
  }

  ignoreMutation() {
    return true;
  }

  destroy() {
    document.removeEventListener("pointerdown", this.onOutside, true);
    this.player?.destroy();
  }
}

// heroicons outline "cog-6-tooth", drawn like the player's own icons.
function gearIcon(): SVGElement {
  const ns = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(ns, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("fill", "none");
  svg.setAttribute("stroke", "currentColor");
  svg.setAttribute("stroke-width", "1.5");
  svg.setAttribute("aria-hidden", "true");
  svg.classList.add("exam-editor__audio-pill-icon");
  for (const d of [
    "M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 0 1 1.37.49l1.296 2.247a1.125 1.125 0 0 1-.26 1.431l-1.003.827c-.293.241-.438.613-.43.992a7.723 7.723 0 0 1 0 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.955.26 1.43l-1.298 2.247a1.125 1.125 0 0 1-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.47 6.47 0 0 1-.22.128c-.331.183-.581.495-.644.869l-.213 1.281c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.019-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 0 1-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 0 1-1.369-.49l-1.297-2.247a1.125 1.125 0 0 1 .26-1.431l1.004-.827c.292-.24.437-.613.43-.991a6.932 6.932 0 0 1 0-.255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 0 1-.26-1.43l1.297-2.247a1.125 1.125 0 0 1 1.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.086.22-.128.332-.183.582-.495.644-.869l.214-1.28Z",
    "M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z",
  ]) {
    const path = document.createElementNS(ns, "path");
    path.setAttribute("stroke-linecap", "round");
    path.setAttribute("stroke-linejoin", "round");
    path.setAttribute("d", d);
    svg.append(path);
  }
  return svg;
}
