defmodule Tasky.Correction.AnswerVariants do
  @moduledoc """
  Das `;` in einer Musterlösung: gültige Alternativen trennen — und dieselbe
  Vorgabe so schreiben, dass sie Lernenden vorgelegt werden kann.

  Ein Antwortfeld kann mehrere richtige Antworten haben; die Lehrperson erfasst
  sie als `"pdf;.pdf"`. Das Trennzeichen ist ein **Autoren**-Format. Beim
  Bewerten wird es aufgelöst (`split/1`), beim Anzeigen an Lernende ebenso —
  sonst steht in der Musterlösung wörtlich `pdf;.pdf`, und wer das `;` nicht
  kennt, liest es als Teil der Antwort.

  Die Regel, was eine Variante ist, steht deshalb **hier** und nur hier:
  `Tasky.Correction.StringComparator`, `Tasky.Tasks.SelfCheck` und die
  Gruppen-Korrektur in `Tasky.Exams` teilen sie sich mit der Anzeige. Liefen
  die beiden auseinander, würde eine Antwort als richtig gelten, die in der
  gezeigten Musterlösung gar nicht steht.

  ## Anzeige

  `humanize_answer/2` schreibt das gespeicherte Payload eines Antwortknotens
  um: `"pdf;.pdf"` wird zu `"pdf oder .pdf"`, vier Varianten werden zu
  `"rasch, flink, zügig oder geschwind"`. Zwei bewusste Grenzen:

    * **Nur bei mehreren Varianten.** Enthält der Text kein `;`, bleibt die
      Knotenliste unangetastet und Formatierungen überleben. Erst ab zwei
      Varianten kollabiert der Inhalt auf einen Textknoten — ein `;` bedeutet
      „Alternativen", da ist Absatzstruktur ohnehin nicht gemeint.
    * **Der Knotentyp entscheidet die Form**, nicht eine Vermutung über den
      Inhalt: `answerBlock` speichert Blockknoten, `lueckentext` Inlineknoten
      (siehe `Tasky.Correction.AnswerKey.extract_answer/2`). Ein `taskItem`
      trägt einen Boolean und geht unverändert durch.

  Umgeschrieben wird ausschliesslich für Lernende. Die Editoren der Lehrperson
  zeigen weiterhin das rohe `;` — dort ist es das Eingabeformat.
  """

  @separator ";"

  # Dieselben zwei Typen, die `Tasky.Correction.AnswerKey` als Textantworten
  # führt. `taskItem` fehlt hier absichtlich: eine Checkbox hat keine Varianten.
  @text_types ["answerBlock", "lueckentext"]

  @doc """
  Die akzeptierten Alternativen eines Musterlösungs-Textes.

  Leerzeichen rundherum und leere Abschnitte fallen weg, `nil` ergibt `[]`.
  """
  @spec split(String.t() | nil) :: [String.t()]
  def split(text) when is_binary(text) do
    text
    |> String.split(@separator)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def split(_text), do: []

  @doc """
  Dieselben Alternativen als deutscher Satz.

      iex> AnswerVariants.humanize("pdf;.pdf")
      "pdf oder .pdf"

      iex> AnswerVariants.humanize("rasch; flink; zügig; geschwind")
      "rasch, flink, zügig oder geschwind"
  """
  @spec humanize(String.t() | nil) :: String.t()
  def humanize(text) do
    case split(text) do
      [] -> ""
      variants -> join(variants)
    end
  end

  @doc """
  Das Antwort-Payload eines Knotens, für Lernende lesbar gemacht.

  `node` ist der Antwortknoten (nur sein `"type"` wird gelesen), `payload` das,
  was `Tasky.Correction.AnswerKey` dafür gespeichert hat. Alles ausser
  `answerBlock` und `lueckentext` geht unverändert durch.
  """
  @spec humanize_answer(map(), term()) :: term()
  def humanize_answer(%{"type" => "answerBlock"}, nodes) when is_list(nodes),
    do: rewrite(nodes, :block)

  def humanize_answer(%{"type" => "lueckentext"}, nodes) when is_list(nodes),
    do: rewrite(nodes, :inline)

  def humanize_answer(_node, payload), do: payload

  @doc """
  Dasselbe über ein ganzes antwortgefülltes Dokument.

  Für die Flächen, die Lernenden die Musterlösung als fertiges Dokument
  vorlegen — die zurückgegebene Prüfung samt PDF und die Lerneinheit ohne
  erfasste Antworten. Antwortknoten sind wie überall Blätter: in ihre Kinder
  wird nicht abgestiegen.
  """
  @spec humanize_doc(map() | nil) :: map() | nil
  def humanize_doc(%{"content" => content} = doc) when is_list(content),
    do: Map.put(doc, "content", walk(content))

  def humanize_doc(doc), do: doc

  ## Intern

  defp join([single]), do: single

  defp join(variants) do
    {init, [last]} = Enum.split(variants, -1)
    Enum.join(init, ", ") <> " oder " <> last
  end

  defp rewrite(nodes, shape) do
    case nodes |> plain_text() |> split() do
      [_single] -> nodes
      [] -> nodes
      variants -> wrap(join(variants), shape)
    end
  end

  defp wrap(text, :inline), do: [text_node(text)]
  defp wrap(text, :block), do: [%{"type" => "paragraph", "content" => [text_node(text)]}]

  defp text_node(text), do: %{"type" => "text", "text" => text}

  defp walk(nodes) when is_list(nodes), do: Enum.map(nodes, &walk_node/1)

  defp walk_node(%{"type" => type, "content" => content} = node)
       when type in @text_types and is_list(content),
       do: Map.put(node, "content", humanize_answer(node, content))

  defp walk_node(%{"type" => type} = node) when type in @text_types, do: node

  defp walk_node(%{"content" => content} = node) when is_list(content),
    do: Map.put(node, "content", walk(content))

  defp walk_node(node), do: node

  defp plain_text(nodes) when is_list(nodes) do
    Enum.map_join(nodes, "", fn
      %{"type" => "text", "text" => text} -> text
      %{"content" => inner} when is_list(inner) -> plain_text(inner)
      _ -> ""
    end)
  end

  defp plain_text(_nodes), do: ""
end
