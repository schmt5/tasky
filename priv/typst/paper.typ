// The blank paper version of an exam (`Tasky.ExamPaper.render_pdf/1`).
//
// Data (`data.json`):
//   exam_name: str, max_points: str | none, doc: Tiptap doc,
//   free_document: bool, lined_pages: int, rules_per_page: int
//
// Mirrors `TaskyWeb.ExamLive.Paper` and the `.paper-view` rules in
// `exam_content_editor.css`, which remain the browser-print fallback.

#import "/tiptap.typ": render-doc, stone

#let field(label, width: 1fr) = stack(
  spacing: 1mm,
  text(size: 7.5pt, fill: stone.s500, label),
  block(width: 100%, height: 7mm, stroke: (bottom: 0.75pt + stone.s600)),
)

#let render(data) = {
  set document(title: data.exam_name + " – Papierversion")
  set page(paper: "a4", margin: (x: 14mm, y: 12mm))
  set text(font: "DM Sans", size: 12pt, fill: stone.s900, lang: "de")
  set par(leading: 0.75em, spacing: 0.75em)

  block(below: 8mm, {
    text(size: 7.5pt, tracking: 0.14em, fill: stone.s500, upper[Papierversion])
    v(1mm)
    block(below: 6mm, text(font: "Instrument Serif", size: 26pt, data.exam_name))
    grid(columns: (2fr, 1fr, 1fr), column-gutter: 6mm, field[Name], field[Klasse], field[Datum])
    v(4mm)
    grid(
      columns: (1fr, 1fr),
      column-gutter: 6mm,
      field(if data.max_points != none [Punkte von #data.max_points] else [Punkte]),
      field[Note],
    )
  })

  render-doc(data.doc, mode: "paper")

  // A free document has no answer fields to size, so the writing space has to
  // be blank pages instead.
  if data.free_document {
    for page in range(1, data.lined_pages + 1) {
      pagebreak()
      block(below: 6mm, grid(
        columns: (2fr, 1fr),
        column-gutter: 6mm,
        align: (left + bottom, right + bottom),
        field[Name],
        text(size: 7.5pt, fill: stone.s500)[Seite #(page + 1) von #(data.lined_pages + 1)],
      ))
      for _ in range(data.rules_per_page) {
        block(width: 100%, height: 9mm, above: 0pt, below: 0pt, stroke: (bottom: 0.75pt + stone.s400))
      }
    }
  }
}
