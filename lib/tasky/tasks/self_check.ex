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

  Das Vokabular ist dasselbe wie in `Tasky.Grading`: `"correct"` oder
  `"wrong"`. Ein `"half"` kann hier nicht entstehen — es gibt niemanden, der
  es setzen würde.
  """

  alias Tasky.Correction.AnswerVariants
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

  Ergänzt wird das Dokument um:

    * `attrs["verdict"]` an jedem geprüften Antwortknoten,
    * einen `solutionHint`-Block hinter jedem Block mit Text-Antwortfeldern,
      der die Musterlösung im selben Feld-Look zeigt.

  Checkboxen bekommen keinen `solutionHint`: dort sagt das Verdikt bereits,
  wie es richtig gewesen wäre. Ist ein Feld von der automatischen Prüfung
  ausgenommen, erscheint die Musterlösung trotzdem — nur eben ohne Verdikt.
  Das ist der Sinn der Ausnahme.
  """
  @spec review_doc(Task.t(), map(), map()) :: map()
  def review_doc(%Task{} = task, base_doc, verdicts) when is_map(verdicts) do
    ctx = %{
      verdicts: verdicts,
      sample: task.sample_solution || %{}
    }

    base_doc = base_doc || %{}
    nodes = doc_nodes(base_doc)

    Map.merge(base_doc, %{"type" => "doc", "content" => expand(nodes, ctx)})
  end

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
        case String.trim(plain_text(node)) do
          "" ->
            "wrong"

          given ->
            if Enum.any?(accepted, &StringComparator.text_match?(given, &1, @match_opts)),
              do: "correct",
              else: "wrong"
        end
    end
  end

  defp verdict_for(_node, _payload, _off?), do: nil

  defp accepted_answers(payload),
    do: payload |> plain_text_from_nodes() |> AnswerVariants.split()

  defp checked?(node), do: node |> Map.get("attrs", %{}) |> Map.get("checked") == true

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

  # Der Anzeigepfad, und nur er: `verdict_for/3` holt sein Payload in
  # `evaluate/2` direkt aus `sample`. Bewertet wird also weiterhin gegen jede
  # einzelne Variante, gezeigt wird der lesbare Satz.
  defp sample_for(node, ctx),
    do: AnswerVariants.humanize_answer(node, Map.get(ctx.sample, answer_id(node)))

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
