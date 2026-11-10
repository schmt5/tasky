// Read-only annotations: the sample-solution hint and the teacher's red text.

import { Node, Mark } from "@tiptap/core";

// Die Musterlösung eines Antwortfelds, in der Vergleichsansicht direkt unter
// der eigenen Antwort — in der Selbstkontrolle einer Lerneinheit wie in der
// zurückgegebenen Prüfung. Eingefügt wird der Knoten ausschliesslich
// serverseitig von `Tasky.Correction.SolutionHints.annotate/4` — darum kein
// Command und keine Input-Rule: er kann nicht in ein Autoren-Dokument geraten.
export const SolutionHint = Node.create({
  name: "solutionHint",
  group: "block",
  content: "block+",

  parseHTML() {
    return [{ tag: "div.solution-hint" }];
  },

  renderHTML({ HTMLAttributes }) {
    return ["div", { ...HTMLAttributes, class: "solution-hint" }, 0];
  },
});

export const TeacherComment = Mark.create({
  name: "teacherComment",

  parseHTML() {
    return [{ tag: "span.teacher-comment" }];
  },

  renderHTML({ HTMLAttributes }) {
    return ["span", { ...HTMLAttributes, class: "teacher-comment" }, 0];
  },

  addCommands() {
    return {
      toggleTeacherComment:
        () =>
        ({ commands }: { commands: any }) =>
          commands.toggleMark(this.name),
    } as any;
  },
});
