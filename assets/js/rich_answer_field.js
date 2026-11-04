import { Editor } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
import { CharacterCount } from "@tiptap/extensions";
import { Highlight } from "@tiptap/extension-highlight";
import { svgIcon } from "./editor_icons";

// The learner's essay field ("Aufsatzfeld"): an answer block with
// `rich: true`, rendered by TaskyWeb.ExamDocHTML as a container whose
// `data-value` holds the answer as Tiptap JSON. This turns it into a small
// editor with just the formatting a learner may use — the same list the
// server keeps when saving (Tasky.Correction.RichAnswer): paragraphs,
// level-4 headings (h3 would cut the exam into parts), lists, blockquotes,
// bold, italic, underline, a yellow highlight.
//
// The ExamAnswersForm hook owns saving: it mounts these fields, reads
// `value()` into its snapshot, and listens for the `input` event every edit
// sends from the container.

// The toolbar, grouped and labelled like the teachers' (react/editor/
// Toolbar.tsx). Heroicons come as `hero-*` classes Tailwind builds from this
// file; the rest are the icons the teachers' toolbar shares.
const GROUPS = [
  {
    label: "Aktionen",
    commands: [
      {
        label: "Rückgängig",
        run: (c) => c.undo(),
        can: (e) => e.can().undo(),
        hero: "hero-arrow-uturn-left",
      },
      {
        label: "Wiederholen",
        run: (c) => c.redo(),
        can: (e) => e.can().redo(),
        hero: "hero-arrow-uturn-right",
      },
    ],
  },
  {
    label: "Schriftart",
    commands: [
      {
        label: "Zwischentitel",
        key: "heading",
        attrs: { level: 4 },
        run: (c) => c.toggleHeading({ level: 4 }),
        icon: "heading",
      },
      {
        label: "Fett",
        key: "bold",
        run: (c) => c.toggleBold(),
        hero: "hero-bold",
      },
      {
        label: "Unterstrichen",
        key: "underline",
        run: (c) => c.toggleUnderline(),
        hero: "hero-underline",
      },
      {
        label: "Kursiv",
        key: "italic",
        run: (c) => c.toggleItalic(),
        hero: "hero-italic",
      },
      // One colour only: the server keeps the mark, never a colour.
      {
        label: "Markieren",
        key: "highlight",
        run: (c) => c.toggleHighlight(),
        hero: "hero-paint-brush",
        bar: true,
      },
    ],
  },
  {
    label: "Listen",
    commands: [
      {
        label: "Aufzählung",
        key: "bulletList",
        run: (c) => c.toggleBulletList(),
        icon: "bulletList",
      },
      {
        label: "Nummerierte Liste",
        key: "orderedList",
        run: (c) => c.toggleOrderedList(),
        icon: "orderedList",
      },
    ],
  },
  {
    label: "Blöcke",
    commands: [
      {
        label: "Zitat",
        key: "blockquote",
        run: (c) => c.toggleBlockquote(),
        icon: "blockquote",
      },
    ],
  },
];

export function mountRichAnswerField(container) {
  const disabled = "disabled" in container.dataset;
  const maxChars = Number(container.dataset.maxChars) || null;
  const label = container.getAttribute("aria-label") || "Aufsatz";

  let content;
  try {
    content = JSON.parse(container.dataset.value || "[]");
  } catch {
    content = [];
  }

  const toolbar = disabled ? null : buildToolbar();
  const body = document.createElement("div");
  body.className = "exam-doc__rich-editor";
  const footer = document.createElement("div");
  footer.className = "exam-doc__rich-footer";
  footer.setAttribute("aria-live", "polite");

  container.replaceChildren(...[toolbar?.el, body, footer].filter(Boolean));

  const editor = new Editor({
    element: body,
    editable: !disabled,
    extensions: [
      StarterKit.configure({
        heading: { levels: [4] },
        code: false,
        codeBlock: false,
        horizontalRule: false,
        link: false,
        strike: false,
        // It keeps an empty paragraph after the last block — in every
        // saved answer.
        trailingNode: false,
      }),
      // The server refuses a save over its limit (RichAnswer.max_chars/0),
      // and with it every other answer in the same snapshot — so the editor
      // stops typing there. It counts block breaks too, so it stops first.
      CharacterCount.configure({ limit: maxChars }),
      Highlight,
    ],
    content: {
      type: "doc",
      content: content.length ? content : [{ type: "paragraph" }],
    },
    editorProps: {
      attributes: {
        // No spell check or autocorrect: in an exam those are aids (the same
        // rule as the native fields and SEB's allowSpellCheck: false).
        spellcheck: "false",
        autocorrect: "off",
        autocapitalize: "off",
        "aria-label": label,
        "aria-multiline": "true",
        role: "textbox",
        class: "exam-doc__rich-input",
      },
    },
    onUpdate: () => {
      updateFooter();
      container.dispatchEvent(new Event("input", { bubbles: true }));
    },
    onSelectionUpdate: () => toolbar?.refresh(),
    onTransaction: () => toolbar?.refresh(),
  });

  // No word count: the footer only speaks up once the limit stops the typing.
  function updateFooter() {
    const full = maxChars != null && editor.storage.characterCount.characters() >= maxChars;
    footer.hidden = !full;
    footer.textContent = full ? "Maximale Länge erreicht" : "";
  }

  function buildToolbar() {
    const el = document.createElement("div");
    el.className = "exam-doc__rich-toolbar";
    el.setAttribute("role", "toolbar");
    el.setAttribute("aria-label", "Formatierung");

    const buttons = [];
    for (const group of GROUPS) {
      const groupEl = document.createElement("div");
      groupEl.className = "exam-doc__rich-group";
      const btns = document.createElement("div");
      btns.className = "exam-doc__rich-group-btns";
      const groupLabel = document.createElement("span");
      groupLabel.className = "exam-doc__rich-group-label";
      groupLabel.textContent = group.label;
      groupEl.append(btns, groupLabel);
      el.appendChild(groupEl);

      for (const cmd of group.commands) buttons.push(buildButton(cmd, btns));
    }

    return {
      el,
      refresh() {
        for (const { cmd, button } of buttons) {
          if (cmd.can) button.disabled = !cmd.can(editor);
          else button.setAttribute("aria-pressed", editor.isActive(cmd.key, cmd.attrs));
        }
      },
    };
  }

  function buildButton(cmd, parent) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "exam-doc__rich-button";
    button.setAttribute("aria-label", cmd.label);
    if (cmd.hero) {
      const icon = document.createElement("span");
      icon.className = `exam-doc__rich-icon ${cmd.hero}`;
      icon.setAttribute("aria-hidden", "true");
      button.appendChild(icon);
    } else {
      button.appendChild(svgIcon(cmd.icon, "exam-doc__rich-icon"));
    }
    if (cmd.bar) {
      const bar = document.createElement("span");
      bar.className = "exam-doc__rich-button-bar";
      button.appendChild(bar);
    }
    // Keep the caret in the text: a mousedown would move focus away.
    button.addEventListener("mousedown", (e) => e.preventDefault());
    button.addEventListener("click", () => cmd.run(editor.chain().focus()).run());
    // daisyUI's tooltip, like the other icon buttons on the page — never
    // the native `title`.
    const tip = document.createElement("div");
    tip.className = "tooltip tooltip-bottom tooltip-delayed";
    tip.dataset.tip = cmd.label;
    tip.appendChild(button);
    parent.appendChild(tip);
    return { cmd, button };
  }

  updateFooter();
  toolbar?.refresh();

  return {
    // The answer as the server takes it: the field's block nodes.
    value: () => editor.getJSON().content || [],
    destroy: () => editor.destroy(),
  };
}
