defmodule Tasky.Correction.RichAnswer do
  @moduledoc """
  Die Antwort eines Aufsatzfelds — eines `answerBlock` mit `rich: true` —
  so, wie Lernende sie schreiben dürfen.

  Das Aufsatzfeld ist ein kleiner Tiptap-Editor in der Lernendenansicht
  (`assets/js/rich_answer_field.js`). Was er sendet, ist Tiptap-JSON aus dem
  Browser und wird hier auf das erlaubte Schema zurückgeschnitten, bevor
  `AnswerKey.merge/2` es ins Dokument setzt:

    * Blöcke: `paragraph`, `heading` (immer Stufe 4 — eine h3 würde die
      Prüfung in Teile schneiden, siehe `Tasky.ExamDoc`), `bulletList`,
      `orderedList`, `listItem`
    * Inline: `text`, `hardBreak`
    * Marks: `bold`, `italic`, `underline`

  Unbekanntes wird nicht abgelehnt, sondern verworfen: Ein unbekannter Knoten
  gibt seine Kinder weiter, damit kein getippter Text verloren geht. Attribute
  ausser `level` und `start` fallen weg. Das Ergebnis ist immer ein gültiger
  `block+`-Inhalt.
  """

  # Wie `PlainAnswers.max_block_chars/0` gegen Missbrauch, aber höher: ein
  # Aufsatz ist länger als eine Antwort.
  @max_chars 60_000
  @max_depth 6

  def max_chars, do: @max_chars

  @doc """
  Schneidet `nodes` (der `content` des Felds, oder ein ganzes `doc`) auf das
  erlaubte Schema zurück. `{:error, :too_long}`, wenn der Text die Obergrenze
  sprengt.
  """
  def sanitize(%{"content" => content}), do: sanitize(content)

  def sanitize(nodes) when is_list(nodes) do
    blocks = blocks(nodes, 0)

    if text_length(blocks) > @max_chars,
      do: {:error, :too_long},
      else: {:ok, blocks}
  end

  def sanitize(_value), do: {:ok, []}

  # --- Blöcke ----------------------------------------------------------------

  defp blocks(nodes, depth) when is_list(nodes) do
    nodes |> Enum.flat_map(&block(&1, depth)) |> merge_loose_inline()
  end

  defp blocks(_nodes, _depth), do: []

  defp block(%{"type" => "paragraph"} = node, _depth),
    do: [with_content(%{"type" => "paragraph"}, inline(children(node)))]

  defp block(%{"type" => "heading"} = node, _depth) do
    [with_content(%{"type" => "heading", "attrs" => %{"level" => 4}}, inline(children(node)))]
  end

  defp block(%{"type" => type} = node, depth) when type in ["bulletList", "orderedList"] do
    if depth >= @max_depth do
      # Zu tief verschachtelt: der Text bleibt, die Liste nicht.
      blocks(children(node), depth)
    else
      items =
        node
        |> children()
        |> Enum.flat_map(&list_item(&1, depth + 1))

      case items do
        [] -> []
        items -> [Map.merge(%{"type" => type, "content" => items}, list_attrs(type, node))]
      end
    end
  end

  # Ein Listenpunkt ausserhalb einer Liste wird zu seinen Blöcken.
  defp block(%{"type" => "listItem"} = node, depth), do: blocks(children(node), depth)

  # Inline-Inhalt auf Blockebene sammelt `merge_loose_inline/1` in Absätze.
  defp block(%{"type" => type} = node, _depth) when type in ["text", "hardBreak"],
    do: [{:inline, inline([node])}]

  defp block(%{"content" => content}, depth) when is_list(content), do: blocks(content, depth)

  defp block(_node, _depth), do: []

  defp list_item(%{"type" => "listItem"} = node, depth) do
    case blocks(children(node), depth) do
      [] -> [%{"type" => "listItem", "content" => [%{"type" => "paragraph"}]}]
      # Ein Listenpunkt beginnt mit einem Absatz (Tiptap: `paragraph block*`).
      [%{"type" => "paragraph"} | _] = content -> [%{"type" => "listItem", "content" => content}]
      content -> [%{"type" => "listItem", "content" => [%{"type" => "paragraph"} | content]}]
    end
  end

  defp list_item(node, depth), do: list_item(%{"type" => "listItem", "content" => [node]}, depth)

  defp list_attrs("orderedList", node) do
    case get_in(node, ["attrs", "start"]) do
      start when is_integer(start) and start > 1 and start < 10_000 ->
        %{"attrs" => %{"start" => start}}

      _ ->
        %{}
    end
  end

  defp list_attrs(_type, _node), do: %{}

  defp merge_loose_inline(blocks) do
    blocks
    |> Enum.chunk_by(&match?({:inline, _}, &1))
    |> Enum.flat_map(fn
      [{:inline, _} | _] = loose ->
        [with_content(%{"type" => "paragraph"}, Enum.flat_map(loose, &elem(&1, 1)))]

      nodes ->
        nodes
    end)
  end

  # --- Inline ----------------------------------------------------------------

  defp inline(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &inline_node/1)

  defp inline_node(%{"type" => "text", "text" => text} = node)
       when is_binary(text) and text != "" do
    case marks(node) do
      [] -> [%{"type" => "text", "text" => text}]
      marks -> [%{"type" => "text", "text" => text, "marks" => marks}]
    end
  end

  defp inline_node(%{"type" => "hardBreak"}), do: [%{"type" => "hardBreak"}]

  # Ein Block mitten im Text (ein eingefügter Absatz in einer Überschrift):
  # sein Text bleibt, getrennt durch einen Zeilenumbruch.
  defp inline_node(%{"type" => type, "content" => content})
       when type in ["paragraph", "heading", "listItem"] and is_list(content),
       do: [%{"type" => "hardBreak"} | inline(content)]

  defp inline_node(%{"content" => content}) when is_list(content), do: inline(content)

  defp inline_node(_node), do: []

  defp marks(node) do
    node
    |> Map.get("marks")
    |> List.wrap()
    |> Enum.flat_map(fn
      %{"type" => type} when type in ["bold", "italic", "underline"] -> [%{"type" => type}]
      _ -> []
    end)
    |> Enum.uniq()
  end

  # --- Helfer ----------------------------------------------------------------

  defp with_content(node, []), do: node
  defp with_content(node, content), do: Map.put(node, "content", content)

  defp children(node) do
    case Map.get(node, "content") do
      content when is_list(content) -> content
      _ -> []
    end
  end

  defp text_length(nodes) when is_list(nodes) do
    Enum.reduce(nodes, 0, fn
      %{"text" => text}, acc -> acc + String.length(text)
      %{"content" => content}, acc -> acc + text_length(content)
      _node, acc -> acc
    end)
  end
end
