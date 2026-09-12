defmodule Tasky.Tasks.SelfCheck do
  @moduledoc """
  Automatische Selbstkontrolle einer Lerneinheit: vergleicht die Antworten
  einer Abgabe mit der Musterlösung und baut daraus das Dokument, das Lernende
  nach der Freigabe zu sehen bekommen.

  Anders als bei Prüfungen wird hier **nichts persistiert**. Lerneinheiten
  werden nicht bewertet (siehe `Tasky.Tasks.TaskSubmission`): es gibt keine
  `block_verdicts`, keine Punkte und keine Note, und die Lehrperson übersteuert
  nichts. Die Verdikte entstehen bei jedem Anzeigen neu aus `submission.content`
  und `task.sample_solution` — ändert die Lehrperson die Musterlösung, stimmt
  die Auswertung sofort.

  Zwei weitere bewusste Unterschiede zur Prüfungs-Autokorrektur
  (`Tasky.AI.BulkCorrectionRunner`):

    * Gepaart wird über `answerId`, nicht über die Position. Antwortdokument
      und Musterlösung stammen beide aus demselben `task.content`, die id ist
      also exakt — `Tasky.Correction.StringComparator.correct_part/4` muss über
      die Reihenfolge gehen, weil dort Teilaufgaben im Spiel sind.
    * Die Marker landen nicht als ✅/❌ im Text (wie in
      `Tasky.AI.NodePatcher.rewrite_markers/2`), sondern als `verdict`-Attribut
      am Antwortknoten. Das Rendern ist damit Sache des Viewers.

  Das Dokument selbst baut `Tasky.Correction.SolutionHints` — dieselbe
  Vergleichsansicht bekommt die zurückgegebene Prüfung.

  Das Vokabular ist dasselbe wie in `Tasky.Grading`: `"correct"` oder
  `"wrong"`. Ein `"half"` kann hier nicht entstehen — es gibt niemanden, der
  es setzen würde.
  """

  alias Tasky.Correction.AnswerVariants
  alias Tasky.Correction.SolutionHints
  alias Tasky.Correction.StringComparator
  alias Tasky.Tasks.Task
  alias Tasky.Tasks.TaskSubmission

  # Dieselben drei Knotentypen wie in `Tasky.Correction.AnswerKey`, und wie
  # dort als Blätter behandelt: in ihre Kinder wird nicht abgestiegen.
  @answer_types ["answerBlock", "lueckentext", "taskItem"]
  @text_types ["answerBlock", "lueckentext"]

  # Gross-/Kleinschreibung ignorieren, aber kein Fuzzy-Matching: "bern" gilt,
  # "Bren" nicht. Alternativen erfasst die Lehrperson wie bei Prüfungen mit
  # `;` in der Musterlösung.
  @match_opts %{ignore_case: true}

  @type summary :: %{verdicts: %{String.t() => String.t()}, correct: integer(), total: integer()}

  @doc """
  Vergleicht die Antworten der Abgabe mit der Musterlösung.

  `total` zählt nur die tatsächlich geprüften Antwortfelder. Nicht geprüft
  werden Felder, die in `task.self_check_off` stehen, und Felder ohne
  brauchbare Musterlösung — ein Feld, das die Lehrperson leer gelassen hat,
  darf keine Quote verderben.
  """
  @spec evaluate(Task.t() | map(), TaskSubmission.t() | map()) :: summary()
  def evaluate(%Task{} = task, %TaskSubmission{} = submission),
    do: evaluate(task, submission.content)

  def evaluate(%Task{} = task, content) when is_map(content) or is_nil(content) do
    nodes = doc_nodes(content)
    sample = task.sample_solution || %{}
    off = MapSet.new(task.self_check_off || [])

    verdicts =
      nodes
      |> collect_answers()
      |> Enum.reduce(%{}, fn {id, node}, acc ->
        case verdict_for(node, Map.get(sample, id), MapSet.member?(off, id)) do
          nil -> acc
          verdict -> Map.put(acc, id, verdict)
        end
      end)

    %{
      verdicts: verdicts,
      correct: Enum.count(verdicts, fn {_id, v} -> v == "correct" end),
      total: map_size(verdicts)
    }
  end

  @doc """
  Das Dokument für die Vergleichsansicht der/des Lernenden.

  `base_doc` ist das Antwortdokument, das angezeigt wird — die Korrektur der
  Lehrperson, sobald es eine gibt, sonst die eigenen Antworten (das entscheidet
  `Tasky.Tasks.answer_doc_for_student/2`). Die Verdikte kommen dagegen immer
  aus `submission.content`: bewertet wird, was die/der Lernende geschrieben
  hat, nicht was die Lehrperson daraus gemacht hat. Über die `answerId` passt
  beides zusammen.

  Angereichert wird das Dokument von `Tasky.Correction.SolutionHints` — was
  dabei entsteht (Verdikt-Attribute, `solutionHint`-Blöcke) steht dort.
  """
  @spec review_doc(Task.t(), map(), map()) :: map()
  def review_doc(%Task{} = task, base_doc, verdicts) when is_map(verdicts),
    do: SolutionHints.annotate(base_doc, task.sample_solution, verdicts)

  ## Auswertung

  defp verdict_for(_node, nil, _off?), do: nil
  defp verdict_for(_node, _payload, true), do: nil

  defp verdict_for(%{"type" => "taskItem"} = node, payload, _off?) when is_boolean(payload) do
    if checked?(node) == payload, do: "correct", else: "wrong"
  end

  defp verdict_for(%{"type" => type} = node, payload, _off?)
       when type in @text_types and is_list(payload) do
    case accepted_answers(payload) do
      # Ein leeres Antwortfeld in der Musterlösung ist keine Vorgabe.
      [] ->
        nil

      accepted ->
        text_verdict(plain_text(node), accepted)
    end
  end

  defp verdict_for(_node, _payload, _off?), do: nil

  defp text_verdict(given, accepted) do
    case String.trim(given) do
      "" ->
        "wrong"

      given ->
        if Enum.any?(accepted, &StringComparator.text_match?(given, &1, @match_opts)),
          do: "correct",
          else: "wrong"
    end
  end

  defp accepted_answers(payload),
    do: payload |> plain_text_from_nodes() |> AnswerVariants.split()

  defp checked?(node), do: node |> Map.get("attrs", %{}) |> Map.get("checked") == true

  ## Gemeinsame Helfer

  defp collect_answers(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, fn
      %{"type" => type} = node when type in @answer_types ->
        case answer_id(node) do
          nil -> []
          id -> [{id, node}]
        end

      %{"content" => content} when is_list(content) ->
        collect_answers(content)

      _ ->
        []
    end)
  end

  defp answer_id(node) do
    case node |> Map.get("attrs", %{}) |> Map.get("answerId") do
      nil -> nil
      id -> to_string(id)
    end
  end

  defp plain_text(node), do: node |> Map.get("content", []) |> plain_text_from_nodes()

  defp plain_text_from_nodes(nodes) when is_list(nodes) do
    Enum.map_join(nodes, "", fn
      %{"type" => "text", "text" => text} -> text
      %{"content" => inner} when is_list(inner) -> plain_text_from_nodes(inner)
      _ -> ""
    end)
  end

  defp plain_text_from_nodes(_), do: ""

  defp doc_nodes(doc) when is_map(doc), do: Map.get(doc, "content", []) || []
  defp doc_nodes(_), do: []
end
