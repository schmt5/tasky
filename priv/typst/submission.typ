// One graded submission (`TaskyWeb.ExamSubmissionPdf`), one file per student
// in the grading export.
//
// Data (`data.json`):
//   exam_name: str, student_name: str,
//   show_points_and_mark: bool, points: str, max_points: str | none, six_hint: str | none,
//   mark: str,
//   sections: [(key: str, heading: str | none, doc: Tiptap doc)]

#import "/tiptap.typ": render-doc, stone

#let stat(label, value) = stack(
  spacing: 1.5mm,
  text(size: 7.5pt, tracking: 0.06em, fill: stone.s500, upper(label)),
  value,
)

#let render(data) = {
  set document(title: data.exam_name + " – " + data.student_name)
  set page(
    paper: "a4",
    margin: (x: 16mm, top: 14mm, bottom: 18mm),
    footer: context {
      set text(size: 8pt, fill: stone.s500)
      grid(
        columns: (1fr, auto),
        [#data.student_name · #data.exam_name],
        [Seite #counter(page).display() von #counter(page).final().first()],
      )
    },
  )
  set text(font: "Nunito", size: 11pt, fill: stone.s900, lang: "de")
  set par(leading: 0.7em, spacing: 0.75em)

  block(
    width: 100%,
    below: 8mm,
    inset: (bottom: 6mm),
    stroke: (bottom: 0.75pt + stone.s200),
    {
      text(weight: "bold", size: 24pt, data.exam_name)
      v(1mm)
      text(size: 10pt, fill: stone.s600, data.student_name)

      if data.show_points_and_mark {
        v(4mm)
        grid(
          columns: (auto, auto),
          column-gutter: 8mm,
          stat("Punkte", {
            text(weight: "semibold", data.points)
            if data.max_points != none {
              text(fill: stone.s400, " / " + data.max_points)
            }
            if data.six_hint != none {
              linebreak()
              text(size: 8pt, fill: stone.s400, data.six_hint)
            }
          }),
          stat("Note", text(weight: "semibold", data.mark)),
        )
      }
    },
  )

  if data.sections.len() == 0 {
    text(size: 10pt, style: "italic", fill: stone.s400)[Keine Inhalte zum Anzeigen ausgewählt.]
  }

  for (i, section) in data.sections.enumerate() {
    if i > 0 { pagebreak() }
    if section.heading != none {
      block(below: 4mm, text(weight: "bold", size: 19pt, section.heading))
    }
    render-doc(section.doc, mode: "review")
  }
}
