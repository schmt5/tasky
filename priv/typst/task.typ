// A learning unit as a printed worksheet or sample solution (`Tasky.TaskPdf`).
//
// Data (`data.json`):
//   title: str (document metadata only), mode: "paper" | "review", doc: Tiptap doc
//
// Only the content: no head, no name fields — the teacher prints it as is.

#import "/tiptap.typ": render-doc, stone

#let render(data) = {
  set document(title: data.title)
  set page(
    paper: "a4",
    margin: (x: 14mm, top: 12mm, bottom: 16mm),
    footer: context {
      set text(size: 8pt, fill: stone.s500)
      align(right)[Seite #counter(page).display() von #counter(page).final().first()]
    },
  )
  set text(font: "Nunito", size: 12pt, fill: stone.s900, lang: "de")
  set par(leading: 0.75em, spacing: 0.75em)

  render-doc(data.doc, mode: data.mode)
}
