defmodule Tasky.Correction.PlainAnswers do
  @moduledoc """
  Antworten als Klartext — die Brücke zwischen den nativen Eingabefeldern der
  Lernendenansicht (`TaskyWeb.ExamDocHTML`) und dem Tiptap-Dokument,
  das in `submission.content` liegt.

  Lernende schreiben in `<input>` und `<textarea>`, nicht mehr in Tiptap. Das
  gespeicherte Format bleibt trotzdem das Dokument: Der Server setzt die
  Antworten mit `Tasky.Correction.AnswerKey.merge/2` in das Gerüst ein. Darum
  laufen Korrektur, Cockpit, PDF, KI und Selbstkontrolle unverändert weiter.

  Zwei Richtungen:

    * `block_text/1`, `gap_text/1` — Dokument → Feldwert. Verlustbehaftet:
      Formatierung fällt weg, Listenpunkte werden zu „• …“, Tabellenzellen
      zu „a | b“. Das trifft nur Antworten, die noch im Tiptap-Editor
      geschrieben wurden.
    * `from_params/2` — Feldwerte → `AnswerKey`-Antworten. Jede Zeile eines
      Antwortblocks wird ein Absatz, eine Lücke ein Text-Node. Ein
      Aufsatzfeld (`answerBlock` mit `rich: true`) schickt Tiptap-JSON statt
      Text; das prüft `Tasky.Correction.RichAnswer`.

  Das Gerüst, in das eingesetzt wird, ist immer das des Servers. Werte für
  Felder, die es dort nicht gibt, fallen weg — der Fragetext ist von aussen
  nicht mehr veränderbar.
  """

  alias Tasky.Correction.Choice
  alias Tasky.Correction.RichAnswer

  # Technische Obergrenzen gegen Missbrauch. Lernende erreichen sie nie; die
  # Felder tragen dieselben Werte als `maxlength`.
  @max_block_chars 20_000
  @max_gap_chars 500

  def max_block_chars, do: @max_block_chars
  def max_gap_chars, do: @max_gap_chars

  @doc """
  Baut aus den Feldwerten der Lernendenansicht die Antworten im Format von
  `AnswerKey.split/1`, gegen das Gerüst `skeleton` geprüft.

  `params` ist `%{"answers" => %{answer_id => wert}, "choices" => %{group_id
  => option_id}}`. Ein Text gehört zu einer Lücke oder einem Antwortblock,
  eine Liste von Tiptap-Knoten zu einem Aufsatzfeld, ein Boolean zu einer
  Multiple-Choice-Option; eine `option_id` muss zur Gruppe
  gehören, `nil` heisst „nichts gewählt“. Alles, was nicht passt, wird
  ignoriert.

  Gibt `{:error, :too_long}` zurück, wenn ein Wert die Obergrenze sprengt.
  """
  def from_params(skeleton, params) when is_map(skeleton) and is_map(params) do
    fields = fields(skeleton)
    answers = params |> Map.get("answers") |> as_map()
    choices = params |> Map.get("choices") |> as_map()

    with {:ok, acc} <- reduce_answers(answers, fields, %{}) do
      {:ok, reduce_choices(choices, fields, acc)}
    end
  end

  defp reduce_answers(answers, fields, acc) do
    Enum.reduce_while(answers, {:ok, acc}, fn {id, value}, {:ok, acc} ->
      case answer(Map.get(fields.answers, to_string(id)), value) do
        {:ok, payload} -> {:cont, {:ok, Map.put(acc, to_string(id), payload)}}
        :ignore -> {:cont, {:ok, acc}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp reduce_choices(choices, fields, acc) do
    Enum.reduce(choices, acc, fn {gid, option}, acc ->
      gid = to_string(gid)

      case choice(Map.get(fields.choices, gid), option) do
        {:ok, selected} -> Map.put(acc, gid, selected)
        :ignore -> acc
      end
    end)
  end

  # `nil` or `""` means nothing chosen; an option must belong to its group.
  defp choice(nil, _option), do: :ignore
  defp choice(_options, option) when option in [nil, ""], do: {:ok, nil}

  defp choice(options, option) when is_binary(option) do
    if MapSet.member?(options, option), do: {:ok, option}, else: :ignore
  end

  defp choice(_options, _option), do: :ignore

  defp answer("answerBlock", text) when is_binary(text) do
    if String.length(text) > @max_block_chars,
      do: {:error, :too_long},
      else: {:ok, block_nodes(text)}
  end

  defp answer("lueckentext", text) when is_binary(text) do
    if String.length(text) > @max_gap_chars,
      do: {:error, :too_long},
      else: {:ok, gap_nodes(text)}
  end

  defp answer("richAnswerBlock", nodes) when is_list(nodes), do: RichAnswer.sanitize(nodes)

  # Ein Aufsatzfeld, dessen Editor nicht startete, schickt nichts; Klartext
  # (ein älterer Client) wird wie beim Antwortblock zu Absätzen.
  defp answer("richAnswerBlock", text) when is_binary(text), do: answer("answerBlock", text)

  defp answer("taskItem", checked) when is_boolean(checked), do: {:ok, checked}
  defp answer(_type, _value), do: :ignore

  @doc "Ein Antwortblock aus Klartext: jede Zeile ein Absatz."
  def block_nodes(text) when is_binary(text) do
    text
    |> normalize_newlines()
    |> String.split("\n")
    |> Enum.map(fn
      "" -> %{"type" => "paragraph"}
      line -> %{"type" => "paragraph", "content" => [text_node(line)]}
    end)
  end

  @doc "Eine Lücke aus Klartext. Zeilenumbrüche werden zu Leerzeichen."
  def gap_nodes(text) when is_binary(text) do
    case text |> normalize_newlines() |> String.replace("\n", " ") do
      "" -> []
      line -> [text_node(line)]
    end
  end

  defp text_node(text), do: %{"type" => "text", "text" => text}

  defp normalize_newlines(text), do: String.replace(text, ~r/\r\n?/, "\n")

  @doc "Der Feldwert eines Antwortblocks: seine Blöcke als Klartext, eine Zeile pro Absatz."
  def block_text(nodes) when is_list(nodes) do
    nodes |> Enum.flat_map(&block_lines(&1, "")) |> Enum.join("\n")
  end

  def block_text(_nodes), do: ""

  @doc "Der Feldwert einer Lücke: ihr Inline-Inhalt als einzeiliger Text."
  def gap_text(nodes) when is_list(nodes) do
    nodes |> inline_text() |> String.replace("\n", " ")
  end

  def gap_text(_nodes), do: ""

  defp block_lines(%{"type" => type} = node, indent) when type in ["bulletList", "taskList"] do
    node |> children() |> Enum.flat_map(&list_item_lines(&1, indent <> "• ", indent))
  end

  defp block_lines(%{"type" => "orderedList"} = node, indent) do
    start =
      case node |> attrs() |> Map.get("start") do
        start when is_integer(start) -> start
        _ -> 1
      end

    node
    |> children()
    |> Enum.with_index(start)
    |> Enum.flat_map(fn {item, n} -> list_item_lines(item, indent <> "#{n}. ", indent) end)
  end

  defp block_lines(%{"type" => "table"} = node, indent) do
    node
    |> children()
    |> Enum.map(fn row ->
      cells =
        Enum.map(children(row), &(children(&1) |> block_text() |> String.replace("\n", " ")))

      indent <> Enum.join(cells, " | ")
    end)
  end

  defp block_lines(%{"type" => type} = node, indent)
       when type in ["paragraph", "heading", "codeBlock"] do
    node |> children() |> inline_text() |> String.split("\n") |> Enum.map(&(indent <> &1))
  end

  defp block_lines(%{"content" => content}, indent) when is_list(content) do
    Enum.flat_map(content, &block_lines(&1, indent))
  end

  defp block_lines(_node, _indent), do: []

  # Die erste Zeile eines Punkts trägt das Zeichen, die weiteren (und
  # verschachtelte Listen) rücken ein.
  defp list_item_lines(item, marker, indent) do
    case item |> children() |> Enum.flat_map(&block_lines(&1, indent <> "  ")) do
      [] ->
        [String.trim_trailing(marker)]

      [first | rest] ->
        [marker <> String.trim_leading(first) | rest]
    end
  end

  defp inline_text(nodes) when is_list(nodes) do
    Enum.map_join(nodes, "", fn
      %{"type" => "text", "text" => text} when is_binary(text) -> text
      %{"type" => "hardBreak"} -> "\n"
      %{"content" => content} when is_list(content) -> inline_text(content)
      _node -> ""
    end)
  end

  @doc """
  Die Antwortfelder eines Dokuments: `%{answers: %{answer_id => typ},
  choices: %{group_id => MapSet von option_ids}}`. Ein Aufsatzfeld hat hier
  den Typ `"richAnswerBlock"`, obwohl es im Dokument ein `answerBlock` ist.
  """
  def fields(%{"content" => content}) when is_list(content) do
    collect(content, %{answers: %{}, choices: %{}})
  end

  def fields(_doc), do: %{answers: %{}, choices: %{}}

  defp collect(nodes, acc) when is_list(nodes) do
    Enum.reduce(nodes, acc, fn
      %{"type" => "choice"} = node, acc ->
        case {Choice.group_id(node), Choice.option_id(node)} do
          {gid, oid} when is_binary(gid) and is_binary(oid) ->
            update_in(acc, [:choices, Access.key(gid, MapSet.new())], &MapSet.put(&1, oid))

          _ ->
            acc
        end

      # Antwortknoten sind Blätter, wie in `AnswerKey`: was darin steckt, setzt
      # `merge/2` nie ein, also ist es auch kein Feld.
      %{"type" => type} = node, acc when type in ["answerBlock", "lueckentext", "taskItem"] ->
        case node |> attrs() |> Map.get("answerId") do
          nil -> acc
          id -> put_in(acc, [:answers, to_string(id)], field_type(type, node))
        end

      %{"content" => content}, acc when is_list(content) ->
        collect(content, acc)

      _node, acc ->
        acc
    end)
  end

  defp field_type("answerBlock", node),
    do: if(rich?(node), do: "richAnswerBlock", else: "answerBlock")

  defp field_type(type, _node), do: type

  @doc "True für ein Aufsatzfeld: einen `answerBlock` mit `rich: true`."
  def rich?(%{"type" => "answerBlock"} = node), do: attrs(node)["rich"] == true
  def rich?(_node), do: false

  defp as_map(map) when is_map(map), do: map
  defp as_map(_value), do: %{}

  defp children(node) when is_map(node) do
    case Map.get(node, "content") do
      content when is_list(content) -> content
      _ -> []
    end
  end

  defp attrs(node) when is_map(node) do
    case Map.get(node, "attrs") do
      attrs when is_map(attrs) -> attrs
      _ -> %{}
    end
  end
end
