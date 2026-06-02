defmodule Tasky.Correction.AnswerKey do
  @moduledoc """
  Splits an answer-filled exam document into an answer-free `content` doc plus
  a map of model answers keyed by a stable per-block id, and merges them back.

  The teacher authors questions and model answers in a single TipTap document.
  On save we `split/1` it: the input blocks are blanked in `content` (what
  students get) and their answers are stored in a side map keyed by each
  block's `answerId`. To reconstruct the answer-filled document (for the
  editor or for correction) we `merge/2` the two back together.

  Answer-bearing nodes are the same three `@answer_types` the correction
  pipeline recognises (`answerBlock`, `lueckentext`, `taskItem`). Mirroring
  `Tasky.AI.NodePatcher`, these nodes are treated as leaves — their children
  are never descended into.

  Answer payloads are type-specific:
    * `answerBlock` / `lueckentext` — the inner content nodes (a list).
    * `taskItem` — the `checked` boolean (the label text stays in `content`).
  """

  @answer_types ["answerBlock", "lueckentext", "taskItem"]

  @doc """
  Assigns a unique `attrs.answerId` to every answer-bearing node that lacks
  one, leaving existing ids untouched. Returns the updated doc.
  """
  def ensure_ids(%{"content" => content} = doc) when is_list(content) do
    seen = collect_ids(content, MapSet.new())
    {new_content, _seen} = assign_walk(content, seen)
    Map.put(doc, "content", new_content)
  end

  def ensure_ids(doc), do: doc

  @doc """
  Splits an answer-filled doc into `{content_doc, answers}` where `content_doc`
  keeps the full structure with input blocks blanked, and `answers` maps each
  block's id (string) to its model answer payload.
  """
  def split(doc) when is_map(doc) do
    doc = ensure_ids(doc)
    content = Map.get(doc, "content", []) || []
    {blanked, answers} = split_walk(content, %{})
    {Map.put(doc, "content", blanked), answers}
  end

  @doc """
  Reconstructs the answer-filled doc by injecting each block's payload from
  `answers` (keyed by `answerId`) into `content_doc`. Blocks without a matching
  entry are left as-is.
  """
  def merge(content_doc, answers) when is_map(content_doc) and is_map(answers) do
    content = Map.get(content_doc, "content", []) || []
    Map.put(content_doc, "content", merge_walk(content, answers))
  end

  def merge(content_doc, _answers), do: content_doc

  @doc """
  Returns the set of `answerId`s (as strings) carried by all answer-bearing
  nodes in the doc. Used to prune orphan entries from the answers map after a
  content edit removed or replaced blocks.
  """
  def block_ids(%{"content" => content}) when is_list(content),
    do: collect_ids(content, MapSet.new())

  def block_ids(_), do: MapSet.new()

  # --- ensure_ids helpers ---

  defp collect_ids(nodes, seen) when is_list(nodes) do
    Enum.reduce(nodes, seen, fn
      %{"type" => type} = node, acc when type in @answer_types ->
        case answer_id(node) do
          nil -> acc
          id -> MapSet.put(acc, to_string(id))
        end

      %{"content" => content}, acc when is_list(content) ->
        collect_ids(content, acc)

      _, acc ->
        acc
    end)
  end

  defp assign_walk(nodes, seen) when is_list(nodes) do
    Enum.map_reduce(nodes, seen, &assign_node/2)
  end

  defp assign_node(%{"type" => type} = node, seen) when type in @answer_types do
    case answer_id(node) do
      nil ->
        id = gen_id(seen)
        attrs = node |> Map.get("attrs", %{}) |> Map.put("answerId", id)
        {Map.put(node, "attrs", attrs), MapSet.put(seen, to_string(id))}

      existing ->
        {node, MapSet.put(seen, to_string(existing))}
    end
  end

  defp assign_node(%{"content" => content} = node, seen) when is_list(content) do
    {new_content, seen} = assign_walk(content, seen)
    {Map.put(node, "content", new_content), seen}
  end

  defp assign_node(node, seen), do: {node, seen}

  defp gen_id(seen) do
    id = :rand.uniform(900_000) + 100_000
    if MapSet.member?(seen, to_string(id)), do: gen_id(seen), else: id
  end

  # --- split helpers ---

  defp split_walk(nodes, answers) when is_list(nodes) do
    Enum.map_reduce(nodes, answers, &split_node/2)
  end

  defp split_node(%{"type" => type} = node, answers) when type in @answer_types do
    {payload, blanked} = extract_answer(type, node)
    {blanked, Map.put(answers, to_string(answer_id(node)), payload)}
  end

  defp split_node(%{"content" => content} = node, answers) when is_list(content) do
    {new_content, answers} = split_walk(content, answers)
    {Map.put(node, "content", new_content), answers}
  end

  defp split_node(node, answers), do: {node, answers}

  defp extract_answer("answerBlock", node) do
    {Map.get(node, "content", []), Map.put(node, "content", [%{"type" => "paragraph"}])}
  end

  defp extract_answer("lueckentext", node) do
    {Map.get(node, "content", []), Map.delete(node, "content")}
  end

  defp extract_answer("taskItem", node) do
    attrs = Map.get(node, "attrs", %{})
    checked = Map.get(attrs, "checked", false)
    {checked, Map.put(node, "attrs", Map.put(attrs, "checked", false))}
  end

  # --- merge helpers ---

  defp merge_walk(nodes, answers) when is_list(nodes) do
    Enum.map(nodes, &merge_node(&1, answers))
  end

  defp merge_node(%{"type" => type} = node, answers) when type in @answer_types do
    case Map.fetch(answers, to_string(answer_id(node))) do
      {:ok, payload} -> apply_answer(type, node, payload)
      :error -> node
    end
  end

  defp merge_node(%{"content" => content} = node, answers) when is_list(content) do
    Map.put(node, "content", merge_walk(content, answers))
  end

  defp merge_node(node, _answers), do: node

  defp apply_answer("taskItem", node, checked) when is_boolean(checked) do
    attrs = node |> Map.get("attrs", %{}) |> Map.put("checked", checked)
    Map.put(node, "attrs", attrs)
  end

  defp apply_answer(_type, node, content) when is_list(content) and content != [] do
    Map.put(node, "content", content)
  end

  defp apply_answer(_type, node, _payload), do: node

  defp answer_id(node) do
    node |> Map.get("attrs", %{}) |> Map.get("answerId")
  end
end
