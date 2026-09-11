defmodule Tasky.ExamPaper do
  @moduledoc """
  Pure algebra for the printed paper version of an exam. No Repo, no structs —
  plain maps in, plain data out, same contract style as `Tasky.ExamDoc`.

  ## What the paper version is

  `exam.content` is already the blank exam: `Tasky.Correction.AnswerKey.split/1`
  empties every answer node when the teacher saves. So there is nothing to blank
  here. What paper needs instead is **room to write by hand** and a little print
  chrome, and that is all this module does:

    * an `answerBlock` gets N empty paragraphs, one per writing line. Its
      content model is `block+` and "empty" already means "one paragraph", so
      more paragraphs is the same shape, just more of it. That is also why the
      teacher can size a box by pressing Enter in it: Enter splits a paragraph,
      Backspace merges two, and no other machinery is involved.
    * a question heading gets `" (4 Punkte)"` appended to its inline text —
      no new attribute, no `::after` rule, and typographically exactly how a
      paper exam reads.
    * a `taskItem` is unchecked, so it prints as an empty box to tick.
    * a `lueckentext` is left alone. On paper it is a fixed-width underline,
      which is purely a CSS concern.

  The transformation is document → document. Rendering stays client-side, so
  the architecture invariant ("no server-side JSON→HTML") holds.

  ## Layout in, layout out

  `paper_doc/2` applies a `%{answer_id => lines}` layout; `extract_layout/1`
  reads one back out of a document the teacher has edited. Those two are
  inverses, and that round trip is what the save path relies on: the paper
  editor sends a whole document like every other editor, and only the line
  counts are persisted (`exam.paper_layout`). Anything else the teacher managed
  to type is dropped on the way in, because `extract_layout/1` counts
  paragraphs and reads nothing else.
  """

  alias Tasky.ExamDoc
  alias Tasky.Grading

  # Handwriting, not print: at 12pt a 189mm text column fits ~90 characters,
  # but a person writing by hand needs roughly double the room per character
  # and a 9mm line. Two lines per point is the ratio that made a 1-point
  # one-word answer and an 8-point essay both come out plausible.
  @lines_per_point 2
  @min_lines 2
  @max_lines 14
  # Used when the question has no points configured at all. Deliberately
  # generous: too little room is unusable, too much only wastes paper.
  @default_lines 4

  @doc """
  The paper document: `content` with the answer boxes sized, the checkboxes
  cleared and the points appended to each question heading.

  Options:

    * `:layout` — `%{answer_id => lines}`, the teacher's own sizing
      (`exam.paper_layout`). Missing entries fall back to the point-derived
      default, so a newly placed answer field is sized sensibly and a stale
      entry for a deleted one is simply ignored.
    * `:sample_solution_points` — `%{part_id => points}`
    * `:sample_solution_block_points` — `%{part_id => %{answer_id => points}}`
    * `:answer_mode` — required, no default (see `ExamDoc.split_content_into_parts/2`)
  """
  def paper_doc(content, opts) when is_list(opts) do
    mode = Keyword.fetch!(opts, :answer_mode)
    layout = normalize_layout(Keyword.get(opts, :layout))
    defaults = default_layout(content, opts)

    content
    |> with_points_in_headings(mode, opts)
    |> apply_layout(layout, defaults)
  end

  @doc """
  Reads a `%{answer_id => lines}` layout out of a paper document the teacher
  has edited.

  Only direct child paragraphs of an `answerBlock` are counted. That is the
  safety net for the save path: the content lock lets the teacher type inside
  an answer field (`stripAnswers` keeps answer content out of the skeleton it
  compares), so stray text can arrive here — and it is discarded rather than
  persisted, because nothing but paragraph *count* is read.
  """
  def extract_layout(doc) when is_map(doc) do
    doc |> Map.get("content", []) |> collect_layout(%{})
  end

  def extract_layout(_), do: %{}

  defp collect_layout(nodes, acc) when is_list(nodes) do
    Enum.reduce(nodes, acc, &collect_layout_node/2)
  end

  defp collect_layout(_, acc), do: acc

  defp collect_layout_node(%{"type" => "answerBlock"} = node, acc) do
    put_line_count(acc, answer_id(node), count_lines(node))
  end

  defp collect_layout_node(%{"content" => content}, acc) when is_list(content) do
    collect_layout(content, acc)
  end

  defp collect_layout_node(_, acc), do: acc

  defp put_line_count(acc, nil, _lines), do: acc
  defp put_line_count(acc, _id, 0), do: acc
  defp put_line_count(acc, id, lines), do: Map.put(acc, id, lines)

  defp count_lines(%{"content" => content}) when is_list(content) do
    Enum.count(content, &match?(%{"type" => "paragraph"}, &1))
  end

  defp count_lines(_), do: 0

  @doc """
  The point-derived starting size of every answer box, `%{answer_id => lines}`.

  This is only a starting point — the teacher adjusts it on the paper view and
  the result lands in `exam.paper_layout`. Points are the signal rather than
  the sample solution because a long answer often has no sample solution
  (essay questions typically don't), while points always exist: without them
  the question cannot be graded.
  """
  def default_layout(content, opts) when is_list(opts) do
    content
    |> answer_block_points(opts)
    |> Map.new(fn {id, points} -> {id, lines_for_points(points)} end)
  end

  @doc """
  Max points per `answerBlock`, `%{answer_id => points}`.

  Same rule as `Tasky.Exams.resolve_block_points/3` — custom distribution when
  there is one, otherwise the question's points split equally — but counted
  over `answerBlock` nodes **only**. `resolve_block_points/3` splits across
  every answer node including checkboxes, which is right for grading and wrong
  for sizing: a 4-point question with one answer field and three checkboxes
  would leave the field with 1 point, i.e. the minimum two lines.
  """
  def answer_block_points(content, opts) when is_list(opts) do
    mode = Keyword.fetch!(opts, :answer_mode)
    part_points = Keyword.get(opts, :sample_solution_points) || %{}
    block_points = Keyword.get(opts, :sample_solution_block_points) || %{}

    content
    |> parts(mode)
    |> Enum.reduce(%{}, fn part, acc ->
      ids = answer_block_ids(part.nodes)
      custom = Map.get(block_points, part.id) || %{}

      Map.merge(acc, part_block_points(ids, custom, Map.get(part_points, part.id)))
    end)
  end

  # One question's answer boxes: the custom distribution if it has one,
  # otherwise the question's total split equally over its boxes.
  defp part_block_points([], _custom, _total), do: %{}

  defp part_block_points(ids, custom, _total) when map_size(custom) > 0 do
    ids
    |> Enum.map(&{&1, Map.get(custom, &1)})
    |> Enum.filter(fn {_id, points} -> is_number(points) end)
    |> Map.new()
  end

  defp part_block_points(ids, _custom, total) when is_number(total) do
    per = total / length(ids)
    Map.new(ids, &{&1, per})
  end

  defp part_block_points(_ids, _custom, _total), do: %{}

  @doc """
  Writing lines for a box worth `points`: two per point, at least #{@min_lines},
  at most #{@max_lines}. `nil` (question without points) gives #{@default_lines}.
  """
  def lines_for_points(nil), do: @default_lines

  def lines_for_points(points) when is_number(points) do
    (points * @lines_per_point)
    |> round()
    |> max(@min_lines)
    |> min(@max_lines)
  end

  def lines_for_points(_), do: @default_lines

  @doc """
  The text appended to a question heading on paper — `" (4 Punkte)"`. Returns
  `nil` for a question with no points configured, so nothing is appended at
  all rather than a misleading `"(0 Punkte)"`.
  """
  def points_suffix(nil), do: nil

  def points_suffix(points) when is_number(points) do
    unit = if points == 1 or points == 1.0, do: "Punkt", else: "Punkte"
    " (#{Grading.format_points(points)} #{unit})"
  end

  def points_suffix(_), do: nil

  @doc "Blank ruled pages appended to a `free_document` exam."
  def lined_page_count, do: 4

  @doc """
  Ruled lines per blank page.

  A4 is 297mm and Gotenberg prints with 0.4in margins top and bottom, leaving
  ~277mm; the page head and the section's own padding eat ~16mm of that. At
  9mm per line, 28 lines (252mm) overflowed onto a second sheet — every blank
  page came out doubled. 24 lines (216mm) leave enough slack that rounding
  cannot spill.
  """
  def rules_per_page, do: 24

  ## --- points in headings ---

  defp with_points_in_headings(content, "free_document", _opts), do: doc_or_empty(content)

  defp with_points_in_headings(content, "answer_fields" = mode, opts) do
    part_points = Keyword.get(opts, :sample_solution_points) || %{}
    # Deliberately no ensure_part_ids/1: it mints *random* ids, and this is a
    # read path that persists nothing. A legacy doc whose headings carry no
    # partId is keyed positionally ("q-1", "q-2") in sample_solution_points,
    # and split_content_into_parts/2 reproduces exactly that fallback — minting
    # ids here would silently stop matching those keys, so the points would
    # vanish from the paper version. Only the save path in Exams stamps ids.
    doc = doc_or_empty(content)

    preamble = ExamDoc.content_preamble(doc, mode)

    parts =
      doc
      |> ExamDoc.split_content_into_parts(mode)
      |> Enum.map(fn part ->
        case points_suffix(Map.get(part_points, part.id)) do
          nil -> part
          suffix -> %{part | nodes: append_to_heading(part.nodes, suffix)}
        end
      end)

    ExamDoc.assemble_parts_into_content(preamble, parts)
  end

  # A part's nodes always start with its h3 (see ExamDoc), so the suffix goes
  # on the first node's inline content.
  defp append_to_heading([heading | rest], suffix) do
    inline = Map.get(heading, "content", []) || []
    [Map.put(heading, "content", inline ++ [%{"type" => "text", "text" => suffix}]) | rest]
  end

  defp append_to_heading([], _suffix), do: []

  ## --- layout ---

  defp apply_layout(doc, layout, defaults) do
    Map.put(doc, "content", resize(Map.get(doc, "content", []) || [], layout, defaults))
  end

  defp resize(nodes, layout, defaults) when is_list(nodes) do
    Enum.flat_map(nodes, &resize_node(&1, layout, defaults))
  end

  defp resize_node(%{"type" => "answerBlock"} = node, layout, defaults) do
    id = answer_id(node)
    lines = Map.get(layout, id) || Map.get(defaults, id) || @default_lines

    [Map.put(node, "content", List.duplicate(%{"type" => "paragraph"}, lines))]
  end

  # The tick is the answer and gets cleared; the label text lives in "content"
  # and must survive. The one place an answer node is not a leaf here.
  defp resize_node(%{"type" => "taskItem"} = node, layout, defaults) do
    attrs = node |> Map.get("attrs", %{}) |> Map.put("checked", false)

    node = Map.put(node, "attrs", attrs)

    case Map.get(node, "content") do
      content when is_list(content) ->
        [Map.put(node, "content", resize(content, layout, defaults))]

      _ ->
        [node]
    end
  end

  # Fixed-width underline on paper — nothing to do to the document.
  defp resize_node(%{"type" => "lueckentext"} = node, _layout, _defaults), do: [node]

  # Defensive: a solution hint cannot occur in exam.content, but if one ever
  # arrives it is the model answer and has no business on a blank sheet.
  defp resize_node(%{"type" => "solutionHint"}, _layout, _defaults), do: []

  defp resize_node(%{"content" => content} = node, layout, defaults) when is_list(content) do
    [Map.put(node, "content", resize(content, layout, defaults))]
  end

  defp resize_node(node, _layout, _defaults), do: [node]

  ## --- helpers ---

  defp parts(content, mode) do
    content
    |> doc_or_empty()
    |> ExamDoc.split_content_into_parts(mode)
  end

  defp answer_block_ids(nodes) when is_list(nodes) do
    nodes
    |> Enum.flat_map(&answer_block_ids_of/1)
    |> Enum.reject(&is_nil/1)
  end

  defp answer_block_ids_of(%{"type" => "answerBlock"} = node), do: [answer_id(node)]

  defp answer_block_ids_of(%{"content" => content}) when is_list(content),
    do: answer_block_ids(content)

  defp answer_block_ids_of(_), do: []

  defp answer_id(node) do
    case node |> Map.get("attrs", %{}) |> Map.get("answerId") do
      id when is_binary(id) and id != "" -> id
      id when is_integer(id) -> Integer.to_string(id)
      _ -> nil
    end
  end

  defp normalize_layout(layout) when is_map(layout) do
    Map.new(layout, fn {k, v} -> {to_string(k), v} end)
    |> Enum.filter(fn {_k, v} -> is_integer(v) and v > 0 end)
    |> Map.new()
  end

  defp normalize_layout(_), do: %{}

  defp doc_or_empty(doc) when is_map(doc) do
    case Map.get(doc, "content") do
      content when is_list(content) -> Map.put(doc, "type", "doc")
      _ -> %{"type" => "doc", "content" => []}
    end
  end

  defp doc_or_empty(_), do: %{"type" => "doc", "content" => []}
end
