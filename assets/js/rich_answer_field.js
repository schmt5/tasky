import { Editor } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
import { CharacterCount } from "@tiptap/extensions";

// The learner's essay field ("Aufsatzfeld"): an answer block with
// `rich: true`, rendered by TaskyWeb.ExamDocHTML as a container whose
// `data-value` holds the answer as Tiptap JSON. This turns it into a small
// editor with just the formatting a learner may use — the same list the
// server keeps when saving (Tasky.Correction.RichAnswer): paragraphs,
// level-4 headings (h3 would cut the exam into parts), lists, bold, italic,
// underline.
//
// The ExamAnswersForm hook owns saving: it mounts these fields, reads
// `value()` into its snapshot, and listens for the `input` event every edit
// sends from the container.

const COMMANDS = [
  { label: "Fett", key: "bold", run: (c) => c.toggleBold(), text: "B", cls: "font-bold" },
  { label: "Kursiv", key: "italic", run: (c) => c.toggleItalic(), text: "I", cls: "italic" },
  {
    label: "Unterstrichen",
    key: "underline",
    run: (c) => c.toggleUnderline(),
    text: "U",
    cls: "underline",
  },
  {
    label: "Zwischentitel",
    key: "heading",
    attrs: { level: 4 },
    run: (c) => c.toggleHeading({ level: 4 }),
    text: "T",
    cls: "font-semibold",
  },
  {
    label: "Aufzählung",
    key: "bulletList",
    run: (c) => c.toggleBulletList(),
    text: "•",
    cls: "",
  },
  {
    label: "Nummerierte Liste",
    key: "orderedList",
    run: (c) => c.toggleOrderedList(),
    text: "1.",
    cls: "",
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
        blockquote: false,
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
    ],
    content: { type: "doc", content: content.length ? content : [{ type: "paragraph" }] },
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

  function updateFooter() {
    const words = editor.storage.characterCount.words();
    const full = maxChars != null && editor.storage.characterCount.characters() >= maxChars;
    footer.textContent =
      `${words} ${words === 1 ? "Wort" : "Wörter"}` + (full ? " · maximale Länge erreicht" : "");
  }

  function buildToolbar() {
    const el = document.createElement("div");
    el.className = "exam-doc__rich-toolbar";
    el.setAttribute("role", "toolbar");
    el.setAttribute("aria-label", "Formatierung");

    const buttons = COMMANDS.map((cmd) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = `exam-doc__rich-button ${cmd.cls}`;
      button.textContent = cmd.text;
      button.setAttribute("aria-label", cmd.label);
      // Keep the caret in the text: a mousedown would move focus away.
      button.addEventListener("mousedown", (e) => e.preventDefault());
      button.addEventListener("click", () => cmd.run(editor.chain().focus()).run());
      el.appendChild(button);
      return { cmd, button };
    });

    return {
      el,
      refresh() {
        for (const { cmd, button } of buttons) {
          const on = editor.isActive(cmd.key, cmd.attrs);
          button.setAttribute("aria-pressed", on ? "true" : "false");
        }
      },
    };
  }

  updateFooter();
  toolbar?.refresh();

  return {
    // The answer as the server takes it: the field's block nodes.
    value: () => editor.getJSON().content || [],
    destroy: () => editor.destroy(),
  };
}
