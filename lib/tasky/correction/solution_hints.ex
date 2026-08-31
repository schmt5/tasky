defmodule Tasky.Correction.SolutionHints do
  @moduledoc """
  Die Musterlösung dort, wo die Antwort steht: baut aus einem Antwortdokument
  die Vergleichsansicht für Lernende.

  Ergänzt wird das übergebene Dokument um zweierlei:

    * `attrs["verdict"]` an jedem Antwortknoten, für den ein Verdikt vorliegt,
    * einen `solutionHint`-Block hinter jedem Block mit Text-Antwortfeldern,
      der die Musterlösung im selben Feld-Look zeigt.

  Beides rendert der gemeinsame Read-only-Viewer (`ExamContentEditor`, Node
  `SolutionHint` und die `[data-verdict]`-Regeln im Stylesheet). Der Marker
  ✅/🟡/❌ kommt damit aus dem CSS und nicht aus dem Text — wer diesen Pfad
  benutzt und ein Dokument mit `Tasky.AI.NodePatcher`-Textmarkern übergibt,
  muss die vorher strippen, sonst steht der Marker doppelt.

  Geteilt von beiden Flächen, die Lernenden eine Musterlösung vorlegen: der
  Selbstkontrolle einer Lerneinheit (`Tasky.Tasks.SelfCheck`) und der
  zurückgegebenen Prüfung (`Tasky.Exams.return_doc_for_learner/3`). Die Regel,
  wie eine Vorgabe neben einer Antwort aussieht, steht deshalb genau hier — die
  beiden Flächen dürfen nicht auseinanderlaufen.

  Gepaart wird ausschliesslich über `answerId`: Antwortdokument und Sample-Map
  stammen in beiden Fällen aus demselben Autoren-Dokument
  (`Tasky.Correction.AnswerKey`), die id ist also exakt.

  Zwei bewusste Grenzen:

    * **Checkboxen bekommen keinen Hinweis.** Bei einem `taskItem` sagt das
      Verdikt bereits, wie es richtig gewesen wäre.
    * **Eine leere Musterlösung ist keine Vorgabe.** Ein leeres Feld unter der
      Antwort wäre nur Lärm.
  """

  alias Tasky.Correction.AnswerVariants

  # Dieselben drei Knotentypen wie in `Tasky.Correction.AnswerKey`, und wie
  # dort als Blätter behandelt: in ihre Kinder wird nicht abgestiegen.
  @answer_types ["answerBlock", "lueckentext", "taskItem"]

  @doc """
  Das Dokument für die Vergleichsansicht.

  `base_doc` ist das Antwortdokument, das angezeigt wird, `sample` die
  Musterlösung als Map `answerId => Payload` (roh, mit `;`), `verdicts` eine Map
  `answerId => "correct" | "half" | "wrong"`. Fehlt zu einer id ein Verdikt,
  bleibt der Knoten unmarkiert — die Musterlösung erscheint trotzdem.

  Das `;` wird beim Bauen des Hinweises aufgelöst
  (`AnswerVariants.humanize_answer/2`): bewertet wurde gegen jede einzelne
  Variante, gezeigt wird die lesbare Liste.
  """
  @spec annotate(map() | nil, map() | nil, map()) :: map()
  def annotate(base_doc, sample, verdicts) when is_map(verdicts) do
    ctx = %{verdicts: verdicts, sample: sample || %{}}
    base_doc = base_doc || %{}

    Map.merge(base_doc, %{"type" => "doc", "content" => expand(doc_nodes(base_doc), ctx)})
  end

  @doc """
  Die `answerId` eines Knotens als String, oder `nil`.
  """
  @spec answer_id(map()) :: String.t() | nil
  def answer_id(node) do
    case node |> Map.get("attrs", %{}) |> Map.get("answerId") do
      nil -> nil
      id -> to_string(id)
    end
  end

  ## Dokument-Transform

  defp expand(nodes, ctx) when is_list(nodes), do: Enum.flat_map(nodes, &expand_node(&1, ctx))

  # Antwortknoten sind Blätter: Verdikt setzen, nicht absteigen.
  defp expand_node(%{"type" => "answerBlock"} = node, ctx) do
    [put_verdict(node, ctx) | hint_for_answer_block(node, ctx)]
  end

  defp expand_node(%{"type" => type} = node, ctx) when type in @answer_types do
    [put_verdict(node, ctx)]
  end

  defp expand_node(%{"content" => content} = node, ctx) when is_list(content) do
    if Enum.any?(content, &lueckentext_with_sample?(&1, ctx)) do
      annotated = Map.put(node, "content", Enum.map(content, &annotate_inline(&1, ctx)))
      [annotated, hint([twin(node, ctx)])]
    else
      [Map.put(node, "content", expand(content, ctx))]
    end
  end

  defp expand_node(node, _ctx), do: [node]

  defp lueckentext_with_sample?(%{"type" => "lueckentext"} = node, ctx),
    do: filled?(sample_for(node, ctx))

  defp lueckentext_with_sample?(_node, _ctx), do: false

  # Eine leere Musterlösung ist keine Vorgabe: ein rotes Feld ohne Inhalt
  # darunter wäre nur Lärm.
  defp filled?(payload) when is_list(payload), do: payload != []
  defp filled?(_payload), do: false

  defp annotate_inline(%{"type" => "lueckentext"} = node, ctx), do: put_verdict(node, ctx)
  defp annotate_inline(node, _ctx), do: node

  defp hint_for_answer_block(node, ctx) do
    payload = sample_for(node, ctx)

    if filled?(payload),
      do: [hint([node |> Map.put("content", payload) |> strip_for_twin()])],
      else: []
  end

  # Der Zwilling zeigt denselben Block mit gefüllten Lücken. Er wird aus dem
  # angezeigten Dokument gebaut, darum fliegen die Anmerkungen der Lehrperson
  # heraus: sie gehören zur Antwort, nicht zur Musterlösung.
  defp twin(%{"content" => content} = node, ctx) do
    filled =
      content
      |> Enum.reject(&teacher_comment?/1)
      |> Enum.map(fn
        %{"type" => "lueckentext"} = child ->
          payload = sample_for(child, ctx)
          if filled?(payload), do: Map.put(child, "content", payload), else: child

        child ->
          child
      end)

    node |> Map.put("content", filled) |> strip_for_twin()
  end

  defp teacher_comment?(%{"marks" => marks}) when is_list(marks),
    do: Enum.any?(marks, &(Map.get(&1, "type") == "teacherComment"))

  defp teacher_comment?(_node), do: false

  # Im Zwilling darf keine `answerId` und kein Verdikt stehen: die id gäbe es
  # sonst zweimal im DOM, und bewertet wird nur die echte Antwort.
  defp strip_for_twin(%{"content" => content} = node) when is_list(content) do
    node
    |> clean_attrs()
    |> Map.put("content", Enum.map(content, &strip_for_twin/1))
  end

  defp strip_for_twin(node), do: clean_attrs(node)

  defp clean_attrs(%{"attrs" => attrs} = node) when is_map(attrs) do
    Map.put(node, "attrs", attrs |> Map.drop(["answerId", "verdict"]))
  end

  defp clean_attrs(node), do: node

  defp hint(nodes), do: %{"type" => "solutionHint", "content" => nodes}

  defp put_verdict(node, ctx) do
    case Map.get(ctx.verdicts, answer_id(node)) do
      nil ->
        node

      verdict ->
        Map.put(node, "attrs", node |> Map.get("attrs", %{}) |> Map.put("verdict", verdict))
    end
  end

  # Der Anzeigepfad, und nur er: bewertet wird gegen jede einzelne Variante
  # (`AnswerVariants.split/1` bei den Bewertern), gezeigt wird die Liste.
  defp sample_for(node, ctx),
    do: AnswerVariants.humanize_answer(node, Map.get(ctx.sample, answer_id(node)))

  defp doc_nodes(doc) when is_map(doc), do: Map.get(doc, "content", []) || []
  defp doc_nodes(_), do: []
end
