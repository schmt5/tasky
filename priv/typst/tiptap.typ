// Renders a Tiptap document (as parsed JSON) to Typst content.
//
// Used by `Tasky.PDF` for every PDF. The document arrives as data (`json(...)`),
// so every string below is inserted as text and never parsed as markup.
//
// Mirrors the node and mark set of `assets/js/react/ExamContentEditor.jsx` and
// the look of `exam_content_editor.css`. A node type unknown here renders its
// children — a new editor extension degrades instead of failing the PDF.
//
// `ctx.mode`:
//   "paper"  — the blank paper exam (`.paper-view`): bordered writing boxes,
//              underline gaps, empty tick boxes.
//   "review" — a submission (answers, verdicts, sample solution).

#let stone = (
  s50: rgb("#fafaf9"),
  s100: rgb("#f5f5f4"),
  s200: rgb("#e7e5e4"),
  s300: rgb("#d6d3d1"),
  s400: rgb("#a8a29e"),
  s500: rgb("#78716c"),
  s600: rgb("#57534e"),
  s700: rgb("#44403c"),
  s900: rgb("#1c1917"),
)

#let violet = (border: rgb("#c4b5fd"), text: rgb("#7c3aed"), fill: rgb("#f5f3ff"))

// The empty-state look of an answer field or gap; violet inside a sample
// solution (`.solution-hint .answer-block`), so the model answer never reads
// as a second answer of the student's.
#let field-fill(ctx) = if ctx.at("hint", default: false) { violet.fill } else { stone.s100 }
#let field-stroke(ctx) = (
  paint: if ctx.at("hint", default: false) { violet.border } else { stone.s400 },
  thickness: 0.75pt,
  dash: "dashed",
)

#let callout-colors = (
  red: (stroke: rgb("#f87171"), fill: rgb("#fee2e2")),
  yellow: (stroke: rgb("#facc15"), fill: rgb("#fef9c3")),
  green: (stroke: rgb("#4ade80"), fill: rgb("#dcfce7")),
  blue: (stroke: rgb("#60a5fa"), fill: rgb("#dbeafe")),
  violet: (stroke: rgb("#a78bfa"), fill: rgb("#ede9fe")),
)

// Verdict colours as in the stylesheet. The sign replaces the browser's colour
// emoji (✅ 🟡 ❌), which no embedded font provides.
#let verdicts = (
  correct: (stroke: rgb("#34d399"), fill: rgb("#ecfdf5"), sign: "✓", ink: rgb("#059669")),
  half: (stroke: rgb("#fcd34d"), fill: rgb("#fffbeb"), sign: "½", ink: rgb("#b45309")),
  wrong: (stroke: rgb("#fca5a5"), fill: rgb("#fef2f2"), sign: "✗", ink: rgb("#dc2626")),
)

#let attrs-of(node) = {
  let a = node.at("attrs", default: none)
  if type(a) == dictionary { a } else { (:) }
}

#let children-of(node) = {
  let c = node.at("content", default: none)
  if type(c) == array { c } else { () }
}

// True when nodes hold no text, image or other leaf — only empty paragraphs.
#let blank(nodes) = nodes.all(n => {
  let kind = n.at("type", default: none)
  if kind == "text" {
    n.at("text", default: "").trim() == ""
  } else if kind in ("paragraph", "doc") or kind == none {
    blank(children-of(n))
  } else {
    false
  }
})

#let verdict-of(node) = {
  let key = attrs-of(node).at("verdict", default: none)
  if type(key) == str and key in verdicts { verdicts.at(key) } else { none }
}

#let verdict-sign(verdict) = text(
  font: "DejaVu Sans Mono",
  weight: "bold",
  fill: verdict.ink,
  size: 0.95em,
  verdict.sign,
)

// The points a returned exam awarded for the field ("1.5", set by
// `Tasky.Exams.learner_points/2`), or none — a self-check has no points.
#let points-of(node) = {
  let p = attrs-of(node).at("points", default: none)
  if type(p) == str and p != "" { p } else { none }
}

// As in the stylesheet: where the points are known, a badge with the points
// replaces the sign. A lone "½" read as "half a point", even for 1.5 of 2.
#let verdict-mark(node, verdict) = {
  let points = points-of(node)
  if points == none {
    verdict-sign(verdict)
  } else {
    box(
      fill: white,
      stroke: 0.75pt + verdict.stroke,
      radius: 6pt,
      inset: (x: 4pt, y: 2pt),
      text(weight: "bold", fill: verdict.ink, size: 0.75em, points + "\u{a0}P."),
    )
  }
}

// --- Inline ------------------------------------------------------------------

#let apply-mark(body, mark) = {
  let kind = mark.at("type", default: none)
  let a = attrs-of(mark)

  if kind == "bold" {
    strong(body)
  } else if kind == "italic" {
    emph(body)
  } else if kind == "underline" {
    underline(body)
  } else if kind == "strike" {
    strike(body)
  } else if kind == "code" {
    box(
      fill: stone.s100,
      inset: (x: 2pt),
      outset: (y: 2pt),
      radius: 2pt,
      text(font: "DejaVu Sans Mono", size: 0.88em, body),
    )
  } else if kind == "link" {
    let href = a.at("href", default: none)
    if type(href) == str and href != "" {
      link(href, underline(text(fill: rgb("#2563eb"), body)))
    } else { body }
  } else if kind == "textStyle" {
    let color = a.at("color", default: none)
    if type(color) == str { text(fill: rgb(color), body) } else { body }
  } else if kind == "highlight" {
    let color = a.at("color", default: none)
    highlight(fill: if type(color) == str { rgb(color) } else { rgb("#fef08a") }, body)
  } else if kind == "teacherComment" {
    highlight(
      fill: rgb("#fef2f2"),
      text(fill: rgb("#dc2626"), underline(stroke: (paint: rgb("#fca5a5"), dash: "dashed"), body)),
    )
  } else {
    body
  }
}

#let render-text(node) = {
  let marks = node.at("marks", default: none)
  let body = [#node.at("text", default: "")]
  if type(marks) == array {
    for mark in marks { body = apply-mark(body, mark) }
  }
  body
}

#let image-placeholder() = box(
  stroke: (paint: stone.s400, dash: "dashed"),
  inset: 6pt,
  radius: 4pt,
  text(size: 0.85em, fill: stone.s500, [Bild nicht verfügbar]),
)

#let render-image(node, inline: false) = {
  let src = attrs-of(node).at("src", default: none)
  if type(src) != str {
    image-placeholder()
  } else if inline {
    box(image(src, height: 1.4em))
  } else {
    block(breakable: false, above: 0.6em, below: 0.6em, image(src, width: auto))
  }
}

// The helpers below and `render-node` are mutually recursive. Typst only lets
// a function call what is defined above it, so `render-node` passes itself
// down as `render-node` / `self`.

#let render-inlines(nodes, ctx, render-node) = {
  for node in nodes { render-node(node, ctx, render-node, inline: true) }
}

#let lueckentext(node, ctx, render-node) = {
  let filled = render-inlines(children-of(node), ctx, render-node)
  let verdict = verdict-of(node)

  if ctx.mode == "paper" {
    box(width: 40mm, stroke: (bottom: 0.75pt + stone.s600), inset: (x: 1mm), outset: (bottom: 2pt), filled)
  } else {
    box(
      fill: if verdict != none { verdict.fill } else { field-fill(ctx) },
      stroke: if verdict != none { 0.75pt + verdict.stroke } else { field-stroke(ctx) },
      radius: 3pt,
      inset: (x: 6pt),
      outset: (y: 3pt),
      {
        if blank(children-of(node)) { h(2.5em) } else { filled }
        if verdict != none { h(0.4em); verdict-mark(node, verdict) }
      },
    )
  }
}

// --- Blocks ------------------------------------------------------------------

#let render-blocks(nodes, ctx, render-node) = {
  for node in nodes { render-node(node, ctx, render-node) }
}

#let heading-block(node, ctx, render-node) = {
  let level = attrs-of(node).at("level", default: 1)
  let size = if level == 1 { 1.8em } else if level == 2 { 1.4em } else { 1.15em }
  let above = if level == 1 { 1.2em } else if level == 2 { 1.1em } else { 1em }
  block(
    sticky: true,
    breakable: false,
    above: above,
    below: 0.6em,
    text(size: size, weight: "semibold", render-inlines(children-of(node), ctx, render-node)),
  )
}

#let answer-block(node, ctx, render-node) = {
  let kids = children-of(node)

  if ctx.mode == "paper" {
    // One empty paragraph per writing line (`Tasky.ExamPaper`), 9mm each.
    block(
      width: 100%,
      breakable: false,
      stroke: 1.5pt + stone.s700,
      inset: (x: 3mm, y: 2mm),
      above: 3mm,
      below: 7mm,
      for kid in kids {
        block(height: 9mm, above: 0pt, below: 0pt, width: 100%, {
          if kid.at("type", default: none) == "paragraph" {
            render-inlines(children-of(kid), ctx, render-node)
          } else {
            render-node(kid, ctx, render-node)
          }
        })
      },
    )
  } else {
    let verdict = verdict-of(node)
    // As in the stylesheet: the points badge sits on the top border like a tag
    // instead of reserving a column, which narrow table cells cannot spare.
    let tagged = verdict != none and points-of(node) != none
    block(
      width: 100%,
      breakable: true,
      fill: if verdict != none { verdict.fill } else { field-fill(ctx) },
      stroke: if verdict != none { 0.75pt + verdict.stroke } else { field-stroke(ctx) },
      radius: 6pt,
      inset: (x: 10pt, y: 8pt),
      above: if tagged { 0.6em + 6pt } else { 0.6em },
      below: 0.6em,
      {
        if tagged {
          place(top + right, dx: -2pt, dy: -11.5pt, verdict-mark(node, verdict))
        } else if verdict != none {
          place(top + right, dx: 2pt, verdict-mark(node, verdict))
        }
        pad(right: if verdict != none and not tagged { 1.4em } else { 0pt }, {
          // Typst has no min-height: an unanswered field still needs a body.
          if blank(kids) { v(1.4em) } else { render-blocks(kids, ctx, render-node) }
        })
      },
    )
  }
}

#let tick-box(checked) = box(
  width: 3.5mm,
  height: 3.5mm,
  stroke: 0.75pt + stone.s700,
  radius: 0.5pt,
  baseline: 0.5mm,
  if checked { align(center + horizon, text(font: "DejaVu Sans Mono", size: 8pt, weight: "bold", "✓")) },
)

// A single-choice radio (`choice`, inline): a circle, filled when chosen. The
// chosen radio takes its group's verdict colour; the right one gets a green
// ring when the group was not answered right, so the sheet shows the answer.
// Paper prints every radio empty.
#let radio-box(node, ctx) = {
  let a = attrs-of(node)
  let paper = ctx.mode == "paper"
  let checked = not paper and a.at("checked", default: false) == true
  let verdict = if paper { none } else { verdict-of(node) }
  let show-correct = (
    not paper and a.at("correct", default: none) == true and verdict != none and verdict != verdicts.correct
  )
  let ink = if checked and verdict != none { verdict.ink } else { stone.s700 }

  box(
    width: 3.5mm,
    height: 3.5mm,
    baseline: 0.5mm,
    outset: if show-correct { 1pt } else { 0pt },
    radius: 50%,
    stroke: if show-correct { 1.5pt + verdicts.correct.stroke } else { 0.75pt + ink },
    if checked { align(center + horizon, circle(radius: 0.9mm, fill: ink, stroke: none)) },
  )
}

#let task-item(node, ctx, render-node, graded-list) = {
  let checked = ctx.mode != "paper" and attrs-of(node).at("checked", default: false) == true
  let verdict = verdict-of(node)

  let row = grid(
    columns: (auto, 1fr, auto),
    column-gutter: 0.6em,
    align: (left + top, left + top, right + top),
    pad(top: 0.15em, tick-box(checked)),
    render-blocks(children-of(node), ctx, render-node),
    if verdict != none { verdict-mark(node, verdict) },
  )

  // As in the stylesheet: the geometry belongs to the list, so ungraded rows
  // line up with their graded neighbours.
  block(
    width: 100%,
    breakable: false,
    above: if graded-list { 2pt } else { 0.4em },
    below: if graded-list { 2pt } else { 0.4em },
    inset: if graded-list { (x: 8pt, y: 5pt) } else { 0pt },
    radius: 6pt,
    fill: if verdict != none { verdict.fill } else { none },
    stroke: if verdict != none { 0.75pt + verdict.stroke } else { none },
    row,
  )
}

#let table-block(node, ctx, render-node) = {
  let rows = children-of(node)
  let columns = calc.max(
    1,
    ..rows.map(row => children-of(row).map(cell => attrs-of(cell).at("colspan", default: 1)).sum(default: 0)),
  )

  let cells = rows
    .map(row => children-of(row).map(cell => {
      let a = attrs-of(cell)
      let header = cell.at("type", default: none) == "tableHeader"
      table.cell(
        colspan: calc.max(1, a.at("colspan", default: 1)),
        rowspan: calc.max(1, a.at("rowspan", default: 1)),
        fill: if header { stone.s100 } else { none },
        {
          set text(weight: "semibold") if header
          render-blocks(children-of(cell), ctx, render-node)
        },
      )
    }))
    .flatten()

  block(
    breakable: false,
    above: 0.75em,
    below: 0.75em,
    table(
      columns: (1fr,) * columns,
      stroke: 0.75pt + stone.s300,
      inset: (x: 7pt, y: 5pt),
      align: left + top,
      ..cells,
    ),
  )
}

#let list-block(node, ctx, render-node, ordered) = {
  let items = children-of(node).map(item => render-blocks(children-of(item), ctx, render-node))
  if ordered {
    let start = attrs-of(node).at("start", default: 1)
    enum(start: if type(start) == int { start } else { 1 }, ..items)
  } else {
    list(..items)
  }
}

#let render-node(node, ctx, self, inline: false) = {
  let kind = node.at("type", default: none)
  let kids = children-of(node)

  if kind == "text" {
    render-text(node)
  } else if kind == "hardBreak" {
    linebreak()
  } else if kind == "lueckentext" {
    lueckentext(node, ctx, self)
  } else if kind == "choice" {
    radio-box(node, ctx)
  } else if kind == "image" {
    render-image(node, inline: inline)
  } else if kind == "paragraph" {
    // An empty paragraph is an empty line in the editor; keep that room.
    if kids.len() == 0 { block(height: 1em, above: 0pt, below: 0.65em) } else { par(render-inlines(kids, ctx, self)) }
  } else if kind == "heading" {
    heading-block(node, ctx, self)
  } else if kind == "bulletList" {
    list-block(node, ctx, self, false)
  } else if kind == "orderedList" {
    list-block(node, ctx, self, true)
  } else if kind == "taskList" {
    let graded = kids.any(item => verdict-of(item) != none)
    block(above: 0.6em, below: 0.6em, for item in kids { task-item(item, ctx, self, graded) })
  } else if kind == "taskItem" {
    task-item(node, ctx, self, verdict-of(node) != none)
  } else if kind == "table" {
    table-block(node, ctx, self)
  } else if kind == "answerBlock" {
    answer-block(node, ctx, self)
  } else if kind == "callout" {
    let color = attrs-of(node).at("color", default: "yellow")
    let c = callout-colors.at(if type(color) == str and color in callout-colors { color } else { "yellow" })
    block(
      width: 100%,
      breakable: false,
      fill: c.fill,
      stroke: 0.75pt + c.stroke,
      radius: 6pt,
      inset: (x: 10pt, y: 8pt),
      above: 0.6em,
      below: 0.6em,
      render-blocks(kids, ctx, self),
    )
  } else if kind == "solutionHint" {
    block(
      width: 100%,
      stroke: (left: 2.25pt + violet.border),
      inset: (left: 0.75em, y: 2pt),
      above: 0.3em,
      below: 0.8em,
      {
        text(size: 8pt, weight: "semibold", tracking: 0.04em, fill: violet.text, upper[Musterlösung])
        v(0.15em)
        set text(fill: violet.text)
        render-blocks(kids, ctx + (hint: true), self)
      },
    )
  } else if kind == "blockquote" {
    block(
      stroke: (left: 2.25pt + stone.s300),
      inset: (left: 0.9em, y: 2pt),
      above: 0.6em,
      below: 0.6em,
      text(fill: stone.s600, render-blocks(kids, ctx, self)),
    )
  } else if kind == "codeBlock" {
    let code = kids.map(k => k.at("text", default: "")).join("", default: "")
    block(width: 100%, breakable: false, fill: stone.s100, radius: 4pt, inset: 8pt, raw(code, block: true))
  } else if kind == "horizontalRule" {
    line(length: 100%, stroke: 0.75pt + stone.s300)
  } else if inline {
    render-inlines(kids, ctx, self)
  } else {
    render-blocks(kids, ctx, self)
  }
}

// Entry point: the content of a Tiptap doc (`{"type": "doc", "content": [...]}`).
#let render-doc(doc, mode: "review") = {
  let ctx = (mode: mode)
  let nodes = if type(doc) == dictionary { children-of(doc) } else if type(doc) == array { doc } else { () }
  render-blocks(nodes, ctx, render-node)
}
