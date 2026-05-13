defmodule Tasky.AI.NodePatcher do
  @moduledoc """
  Helpers to send only verdict-patches to/from the AI correction client.

  Before calling the LLM:
    * `annotate/1` walks the student submission nodes, assigns a sequential
      `__ai_id` attribute to every answer-bearing node (`answerBlock`,
      `lueckentext`, `taskItem`), and strips any trailing ✅/❌ markers from
      text leaves inside those nodes (so re-runs start clean).

  After the LLM returns a `%{id => verdict}` map:
    * `apply_verdicts/2` walks the annotated nodes again, appends ✅/❌
      to the last text leaf inside each answer node, and removes the
      `__ai_id` attribute. Answer nodes for which the LLM returned no
      verdict are left unmarked (but `__ai_id` is still removed).

  This keeps Claude responsible only for the verdict decisions and points
  awarded, never for re-emitting the document structure.
  """

  @answer_types ["answerBlock", "lueckentext", "taskItem"]
  @trailing_marker_regex ~r/\s*[✅❌🟡]\s*$/u

  @doc """
  Returns the ordered list of answer-bearing nodes within the given
  nodes list, paired with their zero-based positional index. Used by
  the power-view to enumerate blocks for keyboard correction.

  Each entry is `%{index: i, type: t, text: plain_text, inferred_verdict: v}`
  where `inferred_verdict` reflects the trailing ✅/🟡/❌ marker on the
  node (or `nil` if absent). Useful as a default verdict when the teacher
  has not yet explicitly overridden the AI's call.
  """
  def list_answer_blocks(nodes) when is_list(nodes) do
    {entries, _} = collect_blocks(nodes, [], 0)
    Enum.reverse(entries)
  end

  defp collect_blocks([], acc, counter), do: {acc, counter}

  defp collect_blocks([%{"type" => type} = node | rest], acc, counter)
       when type in @answer_types do
    raw_text = node |> Map.get("content", []) |> extract_plain_text()
    text = raw_text |> strip_marker_text()
    inferred = infer_verdict_from_text(raw_text)

    entry = %{index: counter, type: type, text: text, inferred_verdict: inferred}
    collect_blocks(rest, [entry | acc], counter + 1)
  end

  defp collect_blocks([%{"content" => content} | rest], acc, counter) when is_list(content) do
    {acc, counter} = collect_blocks(content, acc, counter)
    collect_blocks(rest, acc, counter)
  end

  defp collect_blocks([_ | rest], acc, counter), do: collect_blocks(rest, acc, counter)

  defp extract_plain_text(content) when is_list(content) do
    content
    |> Enum.map(fn
      %{"type" => "text", "text" => t} -> t
      %{"content" => inner} when is_list(inner) -> extract_plain_text(inner)
      _ -> ""
    end)
    |> Enum.join("")
  end

  defp extract_plain_text(_), do: ""

  defp strip_marker_text(text) when is_binary(text) do
    text
    |> String.replace(@trailing_marker_regex, "")
    |> String.trim()
  end

  defp infer_verdict_from_text(text) when is_binary(text) do
    trimmed = String.trim_trailing(text)

    cond do
      String.ends_with?(trimmed, "✅") -> "correct"
      String.ends_with?(trimmed, "🟡") -> "half"
      String.ends_with?(trimmed, "❌") -> "wrong"
      true -> nil
    end
  end

  defp infer_verdict_from_text(_), do: nil

  @doc """
  Rewrites the trailing ✅/❌/🟡 markers on answer-bearing nodes within
  the given nodes list, addressed by their positional index.

  `verdicts` is a map `%{index_int_or_str => "correct" | "half" | "wrong" | nil}`.
  An index not present in the map (or mapped to `nil`/unknown) yields no marker
  (any pre-existing marker is stripped).
  """
  def rewrite_markers(nodes, verdicts) when is_list(nodes) and is_map(verdicts) do
    normalized =
      Enum.into(verdicts, %{}, fn {k, v} ->
        {to_string(k), v}
      end)

    {new_nodes, _} = rewrite_walk(nodes, normalized, 0)
    new_nodes
  end

  defp rewrite_walk(nodes, verdicts, counter) when is_list(nodes) do
    Enum.map_reduce(nodes, counter, fn node, c -> rewrite_node(node, verdicts, c) end)
  end

  defp rewrite_node(%{"type" => type} = node, verdicts, counter) when type in @answer_types do
    verdict = Map.get(verdicts, Integer.to_string(counter))
    marker = power_marker(verdict)

    content = Map.get(node, "content")

    new_content =
      cond do
        is_list(content) and marker ->
          content |> strip_markers() |> append_marker_to_last_text(marker)

        is_list(content) ->
          strip_markers(content)

        true ->
          content
      end

    {put_content(node, new_content), counter + 1}
  end

  defp rewrite_node(%{"content" => content} = node, verdicts, counter) when is_list(content) do
    {new_content, new_counter} = rewrite_walk(content, verdicts, counter)
    {Map.put(node, "content", new_content), new_counter}
  end

  defp rewrite_node(node, _verdicts, counter), do: {node, counter}

  defp power_marker("correct"), do: "✅"
  defp power_marker("half"), do: "🟡"
  defp power_marker("wrong"), do: "❌"
  defp power_marker(_), do: nil

  @doc """
  Returns `{annotated_nodes, answer_count}`.
  `answer_count` is how many `__ai_id`s were assigned (the number of
  answer nodes Claude is expected to return verdicts for).
  """
  def annotate(nodes) when is_list(nodes) do
    walk_annotate(nodes, 0)
  end

  @doc """
  Applies the verdict map back to annotated nodes.
  `verdicts` is `%{"1" => "correct", "2" => "incorrect", ...}`.
  Returns the corrected nodes with markers appended and `__ai_id`
  attributes removed.
  """
  def apply_verdicts(nodes, verdicts) when is_list(nodes) and is_map(verdicts) do
    Enum.map(nodes, &apply_to_node(&1, verdicts))
  end

  defp walk_annotate(nodes, counter) when is_list(nodes) do
    Enum.map_reduce(nodes, counter, &annotate_node/2)
  end

  defp annotate_node(%{"type" => type} = node, counter) when type in @answer_types do
    id = Integer.to_string(counter + 1)
    attrs = node |> Map.get("attrs", %{}) |> Map.put("__ai_id", id)

    cleaned_content =
      case Map.get(node, "content") do
        content when is_list(content) -> strip_markers(content)
        other -> other
      end

    annotated =
      node
      |> Map.put("attrs", attrs)
      |> put_content(cleaned_content)

    {annotated, counter + 1}
  end

  defp annotate_node(%{"content" => content} = node, counter) when is_list(content) do
    {new_content, new_counter} = walk_annotate(content, counter)
    {Map.put(node, "content", new_content), new_counter}
  end

  defp annotate_node(node, counter), do: {node, counter}

  defp strip_markers(content) when is_list(content) do
    Enum.map(content, fn
      %{"type" => "text", "text" => text} = leaf ->
        Map.put(leaf, "text", Regex.replace(@trailing_marker_regex, text, ""))

      %{"content" => inner} = node when is_list(inner) ->
        Map.put(node, "content", strip_markers(inner))

      other ->
        other
    end)
  end

  defp apply_to_node(%{"type" => type, "attrs" => %{"__ai_id" => id} = attrs} = node, verdicts)
       when type in @answer_types do
    marker = verdict_marker(Map.get(verdicts, id))

    content = Map.get(node, "content")

    new_content =
      if marker && is_list(content) do
        append_marker_to_last_text(content, marker)
      else
        content
      end

    new_attrs = Map.delete(attrs, "__ai_id")

    node
    |> put_attrs(new_attrs)
    |> put_content(new_content)
  end

  defp apply_to_node(%{"content" => content} = node, verdicts) when is_list(content) do
    Map.put(node, "content", apply_verdicts(content, verdicts))
  end

  defp apply_to_node(node, _verdicts), do: node

  defp verdict_marker("correct"), do: "✅"
  defp verdict_marker("incorrect"), do: "❌"
  defp verdict_marker(_), do: nil

  defp append_marker_to_last_text(content, marker) do
    {new_reversed, _found} =
      content
      |> Enum.reverse()
      |> do_append(marker, false)

    Enum.reverse(new_reversed)
  end

  defp do_append([], _marker, found), do: {[], found}

  defp do_append([head | tail], marker, true) do
    {rest, _} = do_append(tail, marker, true)
    {[head | rest], true}
  end

  defp do_append([%{"type" => "text", "text" => text} = leaf | rest], marker, false) do
    {[Map.put(leaf, "text", "#{text} #{marker}") | rest], true}
  end

  defp do_append([%{"content" => inner} = node | rest], marker, false) when is_list(inner) do
    reversed_inner = Enum.reverse(inner)

    case do_append(reversed_inner, marker, false) do
      {new_reversed, true} ->
        new_inner = Enum.reverse(new_reversed)
        {[Map.put(node, "content", new_inner) | rest], true}

      {_, false} ->
        {tail, found_in_tail} = do_append(rest, marker, false)
        {[node | tail], found_in_tail}
    end
  end

  defp do_append([other | rest], marker, false) do
    {tail, found} = do_append(rest, marker, false)
    {[other | tail], found}
  end

  defp put_attrs(node, attrs) when attrs == %{}, do: Map.delete(node, "attrs")
  defp put_attrs(node, attrs), do: Map.put(node, "attrs", attrs)

  defp put_content(node, nil), do: node
  defp put_content(node, content), do: Map.put(node, "content", content)
end
