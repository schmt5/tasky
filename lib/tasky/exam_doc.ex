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

  @answer_node_types ["answerBlock", "lueckentext", "taskItem"]

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

  With `"answer_fields"`, each part begins with a level-3 heading (`h3`) which
  represents the question. Anything before the first `h3` is *preamble* (intro
  / instructions) and is NOT returned — use `content_preamble/2` to access it.

  With `"free_document"` there are no questions: the whole document is one
  part under `free_document_part_id/0`, and the preamble is empty. Everything
  downstream (points per part, corrected parts, the correction editor) then
  works on an essay without knowing it is one.

  Returns a list of `%{id, label, nodes}`:
    * `id` — the heading's stable `partId`, or positional `"q-N"` fallback
    * `label` — the heading's inline text content, or fallback `"Frage N"`
    * `nodes` — the part's nodes, starting with the leading `h3` node

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
    nodes = Map.get(doc, "content", []) || []

    {parts, current} = Enum.reduce(nodes, {[], nil}, &split_step/2)

    parts = if current, do: [current | parts], else: parts
    Enum.reverse(parts)
  end

  def split_content_into_parts(_doc, mode) when mode in ["answer_fields", "free_document"],
    do: []

  defp split_step(node, {parts, current}) when is_map(node) do
    cond do
      question_heading?(node) ->
        part = build_part_from_heading(node, length(parts) + count_if(current))
        parts = if current, do: [current | parts], else: parts
        {parts, part}

      current ->
        {parts, %{current | nodes: current.nodes ++ [node]}}

      true ->
        # pre-first-question content = preamble; ignore here
        {parts, nil}
    end
  end

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
  Returns the preamble — nodes before the first level-3 heading. Empty list
  if the document has no preamble (starts with an h3) or no h3 headings.

  Always empty for `"free_document"`: there the single part already covers the
  whole document, so a preamble would duplicate it on reassembly.
  """
  def content_preamble(_doc, "free_document"), do: []

  def content_preamble(doc, "answer_fields") when is_map(doc) do
    (doc |> Map.get("content", []) || [])
    |> Enum.take_while(fn n -> not question_heading?(n) end)
  end

  def content_preamble(_doc, "answer_fields"), do: []

  @doc """
  Reassembles a TipTap doc from a preamble (nodes before the first question)
  and a list of parts (as returned by `split_content_into_parts/2`).

  Each part's `nodes` already includes its leading `question` node, so the
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
  Labels for the answer blocks of a part's nodes, keyed by block index: the
  inline text immediately preceding each answer node (or the preceding table
  cell for the "Begriff | [Antwort]" layout).
  """
  def answer_block_labels(nodes) when is_list(nodes) do
    {labels, _, _} = walk_labels(nodes, %{}, "", 0)
    labels
  end

  defp walk_labels(nodes, labels, buffer, counter) when is_list(nodes) do
    Enum.reduce(nodes, {labels, buffer, counter}, fn node, {l, b, c} ->
      visit_label(node, l, b, c)
    end)
  end

  defp visit_label(%{"type" => type}, labels, buffer, counter)
       when type in @answer_node_types do
    label =
      case String.trim(buffer || "") do
        "" -> nil
        t -> t
      end

    {Map.put(labels, counter, label), "", counter + 1}
  end

  defp visit_label(%{"type" => "text", "text" => t}, labels, buffer, counter)
       when is_binary(t) do
    {labels, (buffer || "") <> t, counter}
  end

  # The leading h3 of a part is the question heading; its inline text is the
  # question label, not a sub-input label. Reset the buffer and skip its
  # content so the first answer block doesn't inherit the question text.
  defp visit_label(
         %{"type" => "heading", "attrs" => %{"level" => 3}},
         labels,
         _buffer,
         counter
       ),
       do: {labels, "", counter}

  # Tables: an answer cell is labelled by the preceding cell in the same row
  # (the common "Begriff | [Antwort]" layout, often repeated across the row).
  # We handle the row explicitly because the linear text buffer has no notion
  # of cell boundaries — without this, the header row and other cells leak
  # into the first answer's label.
  defp visit_label(%{"type" => "tableRow", "content" => cells}, labels, _buffer, counter)
       when is_list(cells) do
    {labels, _prev, counter} =
      Enum.reduce(cells, {labels, nil, counter}, fn cell, {l, prev, c} ->
        if cell_contains_answer?(cell) do
          {l2, c2} = label_answers(cell, l, prev, c)
          {l2, nil, c2}
        else
          {l, cell_text(cell), c}
        end
      end)

    {labels, "", counter}
  end

  defp visit_label(%{"content" => content}, labels, buffer, counter) when is_list(content) do
    walk_labels(content, labels, buffer, counter)
  end

  defp visit_label(_, labels, buffer, counter), do: {labels, buffer, counter}

  defp label_answers(%{"type" => type}, labels, label, counter)
       when type in @answer_node_types do
    normalized =
      case String.trim(label || "") do
        "" -> nil
        t -> t
      end

    {Map.put(labels, counter, normalized), counter + 1}
  end

  defp label_answers(%{"content" => content}, labels, label, counter) when is_list(content) do
    Enum.reduce(content, {labels, counter}, fn node, {l, c} ->
      label_answers(node, l, label, c)
    end)
  end

  defp label_answers(_, labels, _label, counter), do: {labels, counter}

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
