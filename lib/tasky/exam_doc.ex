defmodule Tasky.ExamDoc do
  @moduledoc """
  Pure Tiptap document algebra for exam docs: splitting into
  question-delimited parts, preamble handling, reassembly, per-block labels
  and stable part ids. No Repo, no structs — plain maps in, plain data out.

  ## Part ids

  Every question heading (`h3`) carries a stable `attrs["partId"]`
  (`"q-" <> random`), assigned by the editor when the question is created and
  by `ensure_part_ids/1` as a server-side fallback for legacy docs. All
  part-keyed data (sample-solution points, AI config, corrected parts) uses
  these ids, so reordering or inserting questions never re-keys anything.
  Docs whose headings still lack ids fall back to positional `"q-1"`, `"q-2"`
  ids until they are re-saved (beta rule: no migration).
  """

  @answer_node_types Tasky.Correction.AnswerKey.answer_types()

  @free_document_part_id "document"

  @doc """
  The part id of a `free_document` exam. Such an exam has no question headings,
  so the whole document is one synthetic part under this fixed id — that is
  what keeps `points_per_part`, `corrected_parts`, `sample_solution_points` and
  the correction UI working unchanged for it.
  """
  def free_document_part_id, do: @free_document_part_id

  @doc """
  Assigns a stable `attrs["partId"]` to every question heading that lacks
  one, leaving existing ids untouched. Returns the updated doc.
  """
  def ensure_part_ids(%{"content" => nodes} = doc) when is_list(nodes) do
    seen =
      nodes
      |> Enum.map(&part_id_of/1)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    {new_nodes, _seen} =
      Enum.map_reduce(nodes, seen, fn node, acc ->
        if question_heading?(node) and is_nil(part_id_of(node)) do
          id = gen_part_id(acc)
          attrs = node |> Map.get("attrs", %{}) |> Map.put("partId", id)
          {Map.put(node, "attrs", attrs), MapSet.put(acc, id)}
        else
          {node, acc}
        end
      end)

    Map.put(doc, "content", new_nodes)
  end

  def ensure_part_ids(doc), do: doc

  defp gen_part_id(seen) do
    id = "q-" <> (:crypto.strong_rand_bytes(4) |> Base.encode32(case: :lower, padding: false))
    if MapSet.member?(seen, id), do: gen_part_id(seen), else: id
  end

  defp part_id_of(%{"type" => "heading", "attrs" => attrs}) when is_map(attrs) do
    case Map.get(attrs, "partId") do
      id when is_binary(id) and id != "" -> id
      _ -> nil
    end
  end

  defp part_id_of(_), do: nil

  @doc """
  Splits a TipTap document into parts, according to the exam's answer mode.

  With `"answer_fields"`, each part is built around a level-3 heading (`h3`)
  which represents the question. A horizontal rule lets the teacher cut
  earlier: the rule and everything after it up to the next `h3` become that
  question's lead-in, instead of trailing the question before. A rule with no
  `h3` after it (before the next rule or the end) is just a line and stays
  where it is. Anything before the first part is *preamble* (intro /
  instructions) and is NOT returned — use `content_preamble/2` to access it.

  With `"free_document"` there are no questions: the whole document is one
  part under `free_document_part_id/0`, and the preamble is empty. Everything
  downstream (points per part, corrected parts, the correction editor) then
  works on an essay without knowing it is one.

  Returns a list of `%{id, label, nodes}`:
    * `id` — the heading's stable `partId`, or positional `"q-N"` fallback
    * `label` — the heading's inline text content, or fallback `"Frage N"`
    * `nodes` — the part's nodes: its lead-in (if any), then the `h3` node

  The mode has no default on purpose: a forgotten call site would silently
  report "no parts" for every essay exam, which reads as an empty exam rather
  than as a bug.
  """
  def split_content_into_parts(doc, "free_document") when is_map(doc) do
    [
      %{
        id: @free_document_part_id,
        label: "Dokument",
        nodes: Map.get(doc, "content", []) || []
      }
    ]
  end

  def split_content_into_parts(doc, "answer_fields") when is_map(doc) do
    doc |> segment() |> elem(1)
  end

  def split_content_into_parts(_doc, mode) when mode in ["answer_fields", "free_document"],
    do: []

  # Preamble and parts in one pass, so the two can never disagree about where
  # the first question starts. Lossless: `preamble ++ parts' nodes` is the
  # document again.
  #
  # `pending` holds the nodes since the last horizontal rule. If a question
  # heading follows, they are that question's lead-in; if another rule or the
  # end of the document comes first, they fall back to where they stand.
  defp segment(doc) do
    nodes = Map.get(doc, "content", []) || []

    {preamble, parts, current, pending} =
      Enum.reduce(nodes, {[], [], nil, nil}, &segment_step/2)

    {preamble, current} = settle(pending, preamble, current)
    parts = if current, do: [current | parts], else: parts
    {preamble, Enum.reverse(parts)}
  end

  defp segment_step(node, {preamble, parts, current, pending}) when is_map(node) do
    cond do
      question_heading?(node) ->
        part = build_part_from_heading(node, length(parts) + count_if(current))
        parts = if current, do: [current | parts], else: parts
        {preamble, parts, %{part | nodes: (pending || []) ++ part.nodes}, nil}

      rule?(node) ->
        {preamble, current} = settle(pending, preamble, current)
        {preamble, parts, current, [node]}

      pending ->
        {preamble, parts, current, pending ++ [node]}

      current ->
        {preamble, parts, %{current | nodes: current.nodes ++ [node]}, nil}

      true ->
        {preamble ++ [node], parts, nil, nil}
    end
  end

  defp settle(nil, preamble, current), do: {preamble, current}
  defp settle(pending, preamble, nil), do: {preamble ++ pending, nil}

  defp settle(pending, preamble, current),
    do: {preamble, %{current | nodes: current.nodes ++ pending}}

  defp rule?(%{"type" => "horizontalRule"}), do: true
  defp rule?(_), do: false

  @doc "True when the node is a question heading (level-3 heading)."
  def question_heading?(%{"type" => "heading", "attrs" => %{"level" => 3}}), do: true
  def question_heading?(_), do: false

  defp count_if(nil), do: 0
  defp count_if(_), do: 1

  defp build_part_from_heading(h, idx) do
    label = heading_text(h) || "Frage #{idx + 1}"
    %{id: part_id_of(h) || "q-#{idx + 1}", label: label, nodes: [h]}
  end

  defp heading_text(%{"content" => content}) when is_list(content) do
    content
    |> Enum.map_join("", fn
      %{"text" => t} when is_binary(t) -> t
      _ -> ""
    end)
    |> case do
      "" -> nil
      t -> t
    end
  end

  defp heading_text(_), do: nil

  @doc """
  Returns the preamble — nodes before the first part (its `h3`, or the rule
  that opens its lead-in). Empty list if the document starts with a part.
  Without any `h3` the whole document is preamble.

  Always empty for `"free_document"`: there the single part already covers the
  whole document, so a preamble would duplicate it on reassembly.
  """
  def content_preamble(_doc, "free_document"), do: []

  def content_preamble(doc, "answer_fields") when is_map(doc) do
    doc |> segment() |> elem(0)
  end

  def content_preamble(_doc, "answer_fields"), do: []

  @doc """
  Reassembles a TipTap doc from a preamble (nodes before the first question)
  and a list of parts (as returned by `split_content_into_parts/2`).

  Each part's `nodes` already includes its lead-in and question heading, so the
  reassembly is just concatenation. Inverse of `split_content_into_parts/2`
  + `content_preamble/2`.
  """
  def assemble_parts_into_content(preamble, parts)
      when is_list(preamble) and is_list(parts) do
    %{
      "type" => "doc",
      "content" => preamble ++ Enum.flat_map(parts, & &1.nodes)
    }
  end

  @doc """
  Replaces every question heading with `fun.(part_id, heading)`, keyed by the
  same ids as `split_content_into_parts/2` — including the positional `"q-N"`
  fallback of old documents. Mints no ids: a read path that stamped random
  ones would stop matching the part-keyed maps (`sample_solution_points`, …).

  A free document has no question headings and comes back unchanged.
  """
  def map_question_headings(doc, "answer_fields", fun) when is_map(doc) and is_function(fun, 2) do
    {preamble, parts} = segment(doc)

    nodes = Enum.flat_map(parts, &map_part_heading(&1, fun))
    Map.put(doc, "content", preamble ++ nodes)
  end

  def map_question_headings(doc, "free_document", _fun) when is_map(doc), do: doc

  # A part's nodes hold exactly one h3, after its lead-in (if any).
  defp map_part_heading(part, fun) do
    Enum.map(part.nodes, &if(question_heading?(&1), do: fun.(part.id, &1), else: &1))
  end

  @doc """
  Labels for the answer blocks of a part's nodes, keyed by block index: the
  inline text immediately preceding each answer node (or the preceding table
  cell for the "Begriff | [Antwort]" layout).
  """
  def answer_block_labels(nodes) when is_list(nodes) do
    {labels, _, _, _} = walk_labels(nodes, %{}, "", 0, MapSet.new())
    labels
  end

  # `seen` holds the radio groups already labelled: a group is one answer, at
  # its first radio (see `Tasky.Correction.Choice`), so its later radios
  # neither take an index nor reset the label buffer.
  defp walk_labels(nodes, labels, buffer, counter, seen) when is_list(nodes) do
    Enum.reduce(nodes, {labels, buffer, counter, seen}, fn node, {l, b, c, s} ->
      visit_label(node, l, b, c, s)
    end)
  end

  defp visit_label(%{"type" => type} = node, labels, buffer, counter, seen)
       when type in @answer_node_types do
    case new_answer(node, seen) do
      # The text between a group's radios is its option labels, not the
      # label of whatever answer follows.
      {false, seen} ->
        {labels, "", counter, seen}

      {true, seen} ->
        label =
          case String.trim(buffer || "") do
            "" -> nil
            t -> t
          end

        {Map.put(labels, counter, label), "", counter + 1, seen}
    end
  end

  defp visit_label(%{"type" => "text", "text" => t}, labels, buffer, counter, seen)
       when is_binary(t) do
    {labels, (buffer || "") <> t, counter, seen}
  end

  # The leading h3 of a part is the question heading; its inline text is the
  # question label, not a sub-input label. Reset the buffer and skip its
  # content so the first answer block doesn't inherit the question text.
  defp visit_label(
         %{"type" => "heading", "attrs" => %{"level" => 3}},
         labels,
         _buffer,
         counter,
         seen
       ),
       do: {labels, "", counter, seen}

  # Tables: an answer cell is labelled by the preceding cell in the same row
  # (the common "Begriff | [Antwort]" layout, often repeated across the row).
  # We handle the row explicitly because the linear text buffer has no notion
  # of cell boundaries — without this, the header row and other cells leak
  # into the first answer's label.
  defp visit_label(%{"type" => "tableRow", "content" => cells}, labels, _buffer, counter, seen)
       when is_list(cells) do
    {labels, _prev, counter, seen} =
      Enum.reduce(cells, {labels, nil, counter, seen}, fn cell, {l, prev, c, s} ->
        if cell_contains_answer?(cell) do
          {l2, c2, s2} = label_answers(cell, l, prev, c, s)
          {l2, nil, c2, s2}
        else
          {l, cell_text(cell), c, s}
        end
      end)

    {labels, "", counter, seen}
  end

  defp visit_label(%{"content" => content}, labels, buffer, counter, seen)
       when is_list(content) do
    walk_labels(content, labels, buffer, counter, seen)
  end

  defp visit_label(_, labels, buffer, counter, seen), do: {labels, buffer, counter, seen}

  defp label_answers(%{"type" => type} = node, labels, label, counter, seen)
       when type in @answer_node_types do
    case new_answer(node, seen) do
      {false, seen} ->
        {labels, counter, seen}

      {true, seen} ->
        normalized =
          case String.trim(label || "") do
            "" -> nil
            t -> t
          end

        {Map.put(labels, counter, normalized), counter + 1, seen}
    end
  end

  defp label_answers(%{"content" => content}, labels, label, counter, seen)
       when is_list(content) do
    Enum.reduce(content, {labels, counter, seen}, fn node, {l, c, s} ->
      label_answers(node, l, label, c, s)
    end)
  end

  defp label_answers(_, labels, _label, counter, seen), do: {labels, counter, seen}

  # Whether an answer node opens a new answer: every node does, except a
  # radio whose group was already counted.
  defp new_answer(%{"type" => "choice"} = node, seen) do
    case Tasky.Correction.Choice.group_id(node) do
      nil -> {false, seen}
      gid -> {not MapSet.member?(seen, gid), MapSet.put(seen, gid)}
    end
  end

  defp new_answer(_node, seen), do: {true, seen}

  defp cell_contains_answer?(%{"type" => type}) when type in @answer_node_types, do: true

  defp cell_contains_answer?(%{"content" => content}) when is_list(content) do
    Enum.any?(content, &cell_contains_answer?/1)
  end

  defp cell_contains_answer?(_), do: false

  defp cell_text(%{"type" => "text", "text" => t}) when is_binary(t), do: t

  defp cell_text(%{"content" => content}) when is_list(content) do
    Enum.map_join(content, "", &cell_text/1)
  end

  defp cell_text(_), do: ""
end
