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

  Wie bei Prüfungen gelten die Korrekturoptionen pro Frage (h3), gespeichert
  in `task.correction_config` (`Tasky.Correction.PartConfig`): Auto-Korrektur
  der Textfelder, Gross-/Kleinschreibung, Satzzeichen, Rechtschreibung und die
  Bewertung von Multiple-Choice. Antwortfelder ausserhalb einer Frage werden
  nicht geprüft. Welches Feld zu welcher Frage gehört, sagt immer
  `task.content`, nie die Abgabe.

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

  alias Tasky.AI.NodePatcher
  alias Tasky.Correction.AnswerVariants
  alias Tasky.Correction.Choice
  alias Tasky.Correction.ImagePin
  alias Tasky.Correction.PartConfig
  alias Tasky.Correction.SolutionHints
  alias Tasky.Correction.StringComparator
  alias Tasky.ExamDoc
  alias Tasky.Tasks.Task
  alias Tasky.Tasks.TaskSubmission

  # Dieselben Knotentypen wie in `Tasky.Correction.AnswerKey`, und wie dort
  # als Blätter behandelt: in ihre Kinder wird nicht abgestiegen.
  @answer_types Tasky.Correction.AnswerKey.answer_types()
  @text_types ["answerBlock", "lueckentext"]

  @type summary :: %{verdicts: %{String.t() => String.t()}, correct: integer(), total: integer()}

  @doc """
  Vergleicht die Antworten der Abgabe mit der Musterlösung.

  `total` zählt, was tatsächlich geprüft wurde: jedes Antwortfeld einzeln,
  eine Checkbox-Liste unter „alles oder nichts“ aber als ein Eintrag. Nicht
  geprüft werden Felder ausserhalb einer Frage, Textfelder einer Frage ohne
  Auto-Korrektur und Felder ohne brauchbare Musterlösung — ein Feld, das die
  Lehrperson leer gelassen hat, darf keine Quote verderben.
  """
  @spec evaluate(Task.t() | map(), TaskSubmission.t() | map()) :: summary()
  def evaluate(%Task{} = task, %TaskSubmission{} = submission),
    do: evaluate(task, submission.content)

  def evaluate(%Task{} = task, content) when is_map(content) or is_nil(content) do
    nodes = doc_nodes(content)
    sample = task.sample_solution || %{}
    fields = fields_by_answer_id(task)

    choices = Choice.groups(nodes)

    verdicts =
      nodes
      |> collect_answers(choices)
      |> Enum.reduce(%{}, fn {id, node}, acc ->
        with %{config: config} <- Map.get(fields, id),
             verdict when not is_nil(verdict) <- verdict_for(node, Map.get(sample, id), config) do
          Map.put(acc, id, verdict)
        else
          _ -> acc
        end
      end)
      |> all_or_nothing(fields)

    units = Enum.group_by(verdicts, fn {id, _v} -> fields[id].unit end, fn {_id, v} -> v end)

    %{
      verdicts: verdicts,
      correct: Enum.count(units, fn {_unit, vs} -> Enum.all?(vs, &(&1 == "correct")) end),
      total: map_size(units)
    }
  end

  # Every answer field under a question of `task.content`, with its question's
  # options and the unit it counts as: itself, or its checkbox list when the
  # question scores checkboxes all or nothing.
  defp fields_by_answer_id(%Task{} = task) do
    task.content
    |> Kernel.||(%{})
    |> ExamDoc.split_content_into_parts("answer_fields")
    |> Enum.flat_map(fn part ->
      config = PartConfig.get(task.correction_config, part.id, PartConfig.defaults(:task))
      all_or_nothing? = PartConfig.checkbox_rule(config) == "all_or_nothing"

      for block <- NodePatcher.list_answer_blocks(part.nodes), block.answer_id do
        {block.answer_id, %{config: config, unit: unit(block, part.id, all_or_nothing?)}}
      end
    end)
    |> Map.new()
  end

  defp unit(%{type: "taskItem", group: group}, part_id, true) when not is_nil(group),
    do: {:list, part_id, group}

  defp unit(block, _part_id, _all_or_nothing?), do: block.answer_id

  # Under "alles oder nichts" a checkbox list is right only as a whole: one
  # wrong box marks every box of the list wrong, as the exam's points would.
  defp all_or_nothing(verdicts, fields) do
    wrong_lists =
      for {id, "wrong"} <- verdicts,
          match?({:list, _, _}, fields[id].unit),
          into: MapSet.new(),
          do: fields[id].unit

    Map.new(verdicts, fn {id, v} ->
      if MapSet.member?(wrong_lists, fields[id].unit), do: {id, "wrong"}, else: {id, v}
    end)
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

  defp verdict_for(_node, nil, _config), do: nil

  # A radio group: right when exactly the sample's radio is chosen.
  defp verdict_for({:choice, group}, payload, _config) when is_binary(payload) do
    if Choice.checked_options(group) == [payload], do: "correct", else: "wrong"
  end

  defp verdict_for(%{"type" => "taskItem"} = node, payload, _config) when is_boolean(payload) do
    if checked?(node) == payload, do: "correct", else: "wrong"
  end

  # An essay field is read by the teacher, never compared with the sample.
  defp verdict_for(%{"type" => "answerBlock", "attrs" => %{"rich" => true}}, _payload, _config),
    do: nil

  defp verdict_for(%{"type" => type} = node, payload, config)
       when type in @text_types and is_list(payload) do
    # Ein leeres Antwortfeld in der Musterlösung ist keine Vorgabe.
    with true <- PartConfig.flag?(config, "auto_correct"),
         [_ | _] = accepted <- accepted_answers(payload) do
      text_verdict(plain_text(node), accepted, StringComparator.match_opts(config))
    else
      _ -> nil
    end
  end

  # A pin image: right when every pin is in its zone. A learning unit has no
  # points to share, so partly right is wrong.
  defp verdict_for(%{"type" => "imagePin"} = node, [_ | _] = payload, _config) do
    case ImagePin.score(ImagePin.pins(node), payload, ImagePin.aspect(node)) do
      {_hits, 0} -> nil
      {total, total} -> "correct"
      _partly -> "wrong"
    end
  end

  defp verdict_for(_node, _payload, _config), do: nil

  defp text_verdict(given, accepted, match_opts) do
    case String.trim(given) do
      "" ->
        "wrong"

      given ->
        if Enum.any?(accepted, &StringComparator.text_match?(given, &1, match_opts)),
          do: "correct",
          else: "wrong"
    end
  end

  defp accepted_answers(payload),
    do: payload |> plain_text_from_nodes() |> AnswerVariants.split()

  defp checked?(node), do: node |> Map.get("attrs", %{}) |> Map.get("checked") == true

  ## Gemeinsame Helfer

  # A radio group is keyed by its `groupId` and stands for all its radios;
  # every radio yields the same pair, and `Enum.reduce` into a map keeps one.
  defp collect_answers(nodes, choices) when is_list(nodes) do
    Enum.flat_map(nodes, fn
      %{"type" => "choice"} = node ->
        case Choice.group_id(node) do
          nil -> []
          gid -> [{gid, {:choice, Map.get(choices, gid)}}]
        end

      %{"type" => type} = node when type in @answer_types ->
        case answer_id(node) do
          nil -> []
          id -> [{id, node}]
        end

      %{"content" => content} when is_list(content) ->
        collect_answers(content, choices)

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
