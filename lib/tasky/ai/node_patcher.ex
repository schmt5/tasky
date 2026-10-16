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

  alias Tasky.Correction.Choice

  @answer_types Tasky.Correction.AnswerKey.answer_types()
  @trailing_marker_regex ~r/\s*[✅❌🟡]\s*$/u

  @doc """
  Returns the ordered list of answer-bearing nodes within the given
  nodes list, paired with their zero-based positional index. Used by
  the power-view to enumerate blocks for keyboard correction.

  Each entry is `%{index: i, answer_id: id, type: t, text: plain_text,
  inferred_verdict: v, checked: c, group: g}` where `answer_id` is the node's
  stable `answerId` attribute as a string (or `nil`), and `inferred_verdict`
  reflects the trailing ✅/🟡/❌ marker on the node (or `nil` if absent).
  Useful as a default verdict when the teacher has not yet explicitly
  overridden the AI's call.

  For a `taskItem`, `text` is the checkbox's label, `checked` whether it is
  ticked, and `group` identifies the checkbox list it belongs to — the index
  of the list's first answer node, so it is the same in the exam, the sample
  solution and every submission. Checkboxes of one list belong together and
  are shown as one question. Other node types carry `checked: nil, group: nil`.
  """
  def list_answer_blocks(nodes) when is_list(nodes) do
    {entries, _} = collect_blocks(nodes, [], 0, nil, Choice.groups(nodes))
    Enum.reverse(entries)
  end

  defp collect_blocks(nodes, acc, counter, group, choices)

  defp collect_blocks([], acc, counter, _group, _choices), do: {acc, counter}

  defp collect_blocks(
         [%{"type" => "taskList", "content" => content} | rest],
         acc,
         counter,
         group,
         choices
       )
       when is_list(content) do
    {acc, next} = collect_blocks(content, acc, counter, counter, choices)
    collect_blocks(rest, acc, next, group, choices)
  end

  # A radio group is one block, at the position of its first radio; the
  # group's later radios add nothing. `text` is the chosen option's label.
  defp collect_blocks([%{"type" => "choice"} = node | rest], acc, counter, group, choices) do
    gid = Choice.group_id(node)

    if is_nil(gid) or Enum.any?(acc, &(&1.type == "choice" and &1.answer_id == gid)) do
      collect_blocks(rest, acc, counter, group, choices)
    else
      choice_group = Map.get(choices, gid)

      entry = %{
        index: counter,
        answer_id: gid,
        type: "choice",
        text: Choice.selected_label(choice_group),
        inferred_verdict: Choice.verdict(choice_group),
        checked: nil,
        group: nil
      }

      collect_blocks(rest, [entry | acc], counter + 1, group, choices)
    end
  end

  defp collect_blocks([%{"type" => type} = node | rest], acc, counter, group, choices)
       when type in @answer_types do
    raw_text = node |> Map.get("content", []) |> extract_plain_text()
    text = raw_text |> strip_marker_text()
    inferred = infer_verdict_from_text(raw_text)

    answer_id =
      case node |> Map.get("attrs", %{}) |> Map.get("answerId") do
        nil -> nil
        id -> to_string(id)
      end

    {checked, group} =
      if type == "taskItem",
        do: {get_in(node, ["attrs", "checked"]) == true, group},
        else: {nil, nil}

    entry = %{
      index: counter,
      answer_id: answer_id,
      type: type,
      text: text,
      inferred_verdict: inferred,
      checked: checked,
      group: group
    }

    collect_blocks(rest, [entry | acc], counter + 1, group, choices)
  end

  defp collect_blocks([%{"content" => content} | rest], acc, counter, group, choices)
       when is_list(content) do
    {acc, counter} = collect_blocks(content, acc, counter, group, choices)
    collect_blocks(rest, acc, counter, group, choices)
  end

  defp collect_blocks([_ | rest], acc, counter, group, choices),
    do: collect_blocks(rest, acc, counter, group, choices)

  defp extract_plain_text(content) when is_list(content) do
    Enum.map_join(content, "", fn
      %{"type" => "text", "text" => t} -> t
      %{"content" => inner} when is_list(inner) -> extract_plain_text(inner)
      _ -> ""
    end)
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

    {new_nodes, _} = rewrite_walk(nodes, normalized, {0, %{}})
    new_nodes
  end

  # `state` is `{counter, %{group_id => index}}`: every radio of a group
  # shares the index its first radio took.
  defp rewrite_walk(nodes, verdicts, state) when is_list(nodes) do
    Enum.map_reduce(nodes, state, fn node, st -> rewrite_node(node, verdicts, st) end)
  end

  # Radios have no text to carry a marker, so the verdict goes on the radio's
  # own `verdict` attribute — on every radio of the group.
  defp rewrite_node(%{"type" => "choice"} = node, verdicts, state) do
    case choice_index(node, state) do
      {nil, state} ->
        {node, state}

      {index, state} ->
        verdict = verdicts |> Map.get(Integer.to_string(index)) |> marker_verdict()
        {Choice.put_attr(node, "verdict", verdict), state}
    end
  end

  defp rewrite_node(%{"type" => type} = node, verdicts, {counter, groups})
       when type in @answer_types do
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

    {put_content(node, new_content), {counter + 1, groups}}
  end

  defp rewrite_node(%{"content" => content} = node, verdicts, state) when is_list(content) do
    {new_content, state} = rewrite_walk(content, verdicts, state)
    {Map.put(node, "content", new_content), state}
  end

  defp rewrite_node(node, _verdicts, state), do: {node, state}

  # The positional index of a radio's group: assigned at its first radio.
  defp choice_index(node, {counter, groups} = state) do
    case Choice.group_id(node) do
      nil ->
        {nil, state}

      gid ->
        case Map.fetch(groups, gid) do
          {:ok, index} -> {index, state}
          :error -> {counter, {counter + 1, Map.put(groups, gid, counter)}}
        end
    end
  end

  defp marker_verdict(v) when v in ["correct", "half", "wrong"], do: v
  defp marker_verdict(_v), do: nil

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
    {annotated, {count, _groups}} = walk_annotate(nodes, {0, %{}})
    {annotated, count}
  end

  @doc """
  Applies the verdict map back to annotated nodes.
  `verdicts` is `%{"1" => "correct", "2" => "wrong", ...}` — the same verdict
  vocabulary `Tasky.Grading` and `block_verdicts` use.
  Returns the corrected nodes with markers appended and `__ai_id`
  attributes removed.
  """
  def apply_verdicts(nodes, verdicts) when is_list(nodes) and is_map(verdicts) do
    Enum.map(nodes, &apply_to_node(&1, verdicts))
  end

  defp walk_annotate(nodes, state) when is_list(nodes) do
    Enum.map_reduce(nodes, state, &annotate_node/2)
  end

  # Every radio of a group carries the group's one `__ai_id`; a stale
  # verdict from an earlier run is dropped, like a text marker.
  defp annotate_node(%{"type" => "choice"} = node, state) do
    case choice_index(node, state) do
      {nil, state} ->
        {node, state}

      {index, state} ->
        annotated =
          node
          |> Choice.put_attr("verdict", nil)
          |> Choice.put_attr("__ai_id", Integer.to_string(index + 1))

        {annotated, state}
    end
  end

  defp annotate_node(%{"type" => type} = node, {counter, groups}) when type in @answer_types do
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

    {annotated, {counter + 1, groups}}
  end

  defp annotate_node(%{"content" => content} = node, state) when is_list(content) do
    {new_content, state} = walk_annotate(content, state)
    {Map.put(node, "content", new_content), state}
  end

  defp annotate_node(node, state), do: {node, state}

  # A marker after formatted text (e.g. a highlighted answer) sits in its own
  # text leaf. Stripping it must drop the leaf: ProseMirror rejects empty text
  # nodes, and Tiptap then silently renders the whole document empty.
  defp strip_markers(content) when is_list(content) do
    Enum.flat_map(content, fn
      %{"type" => "text", "text" => text} = leaf ->
        case Regex.replace(@trailing_marker_regex, text, "") do
          "" -> []
          stripped -> [Map.put(leaf, "text", stripped)]
        end

      %{"content" => inner} = node when is_list(inner) ->
        [Map.put(node, "content", strip_markers(inner))]

      other ->
        [other]
    end)
  end

  defp apply_to_node(%{"type" => "choice", "attrs" => %{"__ai_id" => id}} = node, verdicts) do
    node
    |> Choice.put_attr("__ai_id", nil)
    |> Choice.put_attr("verdict", verdicts |> Map.get(id) |> marker_verdict())
  end

  defp apply_to_node(%{"type" => type, "attrs" => %{"__ai_id" => id} = attrs} = node, verdicts)
       when type in @answer_types do
    marker = power_marker(Map.get(verdicts, id))

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

  defp append_marker_to_last_text(content, marker) do
    {new_reversed, _found} =
      content
      |> Enum.reverse()
      |> do_append(marker, false)

    Enum.reverse(new_reversed)
  end

  defp do_append([], _marker, found), do: {[], found}

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
