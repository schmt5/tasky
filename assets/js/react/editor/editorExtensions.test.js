// Run with `mix assets.test`: esbuild bundles this file for Node, `node --test`
// runs it. Both cases below rendered a returned exam as a blank page.

import { test } from "node:test";
import assert from "node:assert/strict";
import { buildEditorExtensions, findUnreadableContent } from "./editorExtensions";

const doc = (...inline) => ({
  type: "doc",
  content: [{ type: "paragraph", content: inline }],
});

// The read-only viewer: no flags set (EDITOR_MODES.readonly sets none of them).
const readonly = buildEditorExtensions();

test("the read-only viewer reads the teacher's red text", () => {
  const corrected = doc(
    { type: "text", text: "Antwort " },
    { type: "text", text: "Tippfehler", marks: [{ type: "teacherComment" }] },
  );

  assert.equal(findUnreadableContent(readonly, corrected), null);
});

test("an empty text node makes the document unreadable", () => {
  const broken = doc({ type: "text", text: "en finissant" }, { type: "text", text: "" });

  assert.match(findUnreadableContent(readonly, broken).message, /Empty text nodes/);
});

test("an unknown mark makes the document unreadable", () => {
  const broken = doc({ type: "text", text: "x", marks: [{ type: "nope" }] });

  assert.match(findUnreadableContent(readonly, broken).message, /no mark type nope/);
});

// No submission: nothing to read, and nothing to report.
test("an empty document is not an error", () => {
  assert.equal(findUnreadableContent(readonly, {}), null);
  assert.equal(findUnreadableContent(readonly, { type: "doc", content: [] }), null);
});

// The blockquote now comes from our own extension instead of StarterKit:
// documents stored before the switch must still read.
test("a stored blockquote stays readable", () => {
  const quoted = {
    type: "doc",
    content: [
      {
        type: "blockquote",
        content: [{ type: "paragraph", content: [{ type: "text", text: "Zitat" }] }],
      },
    ],
  };

  assert.equal(findUnreadableContent(readonly, quoted), null);
  assert.equal(findUnreadableContent(buildEditorExtensions({ lockContent: true }), quoted), null);
});

// The rule cuts a question short (Tasky.ExamDoc); every editor that shows
// the exam must read it, the locked sample solution as much as the viewer.
test("a horizontal rule is readable", () => {
  const ruled = {
    type: "doc",
    content: [
      { type: "paragraph", content: [{ type: "text", text: "Frage 1" }] },
      { type: "horizontalRule" },
      { type: "paragraph", content: [{ type: "text", text: "Kontext" }] },
    ],
  };

  assert.equal(findUnreadableContent(readonly, ruled), null);
  assert.equal(findUnreadableContent(buildEditorExtensions({ lockContent: true }), ruled), null);
});

// An audio block must read in every editor that shows the content, or the
// whole document opens empty.
test("an audio block is readable", () => {
  const withAudio = {
    type: "doc",
    content: [
      {
        type: "audio",
        attrs: { audioId: "a1", src: "/uploads/exams/1/a.mp3", title: "Hörtext", maxPlays: 2 },
      },
    ],
  };

  assert.equal(findUnreadableContent(readonly, withAudio), null);
  assert.equal(findUnreadableContent(buildEditorExtensions({ lockContent: true }), withAudio), null);
});
