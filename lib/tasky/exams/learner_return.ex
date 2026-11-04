defmodule Tasky.Exams.LearnerReturn do
  @moduledoc """
  What a learner sees of their corrected exam once it is returned: the
  sample solution in learner form, their verdicts and points, and the
  document with the solution hung under each answer. Read-only; called through
  the `Tasky.Exams` facade.
  """

  alias Tasky.AI.NodePatcher
  alias Tasky.Correction.AnswerVariants
  alias Tasky.Correction.SolutionHints
  alias Tasky.ExamDoc
  alias Tasky.Exams
  alias Tasky.Exams.Exam
  alias Tasky.Exams.ExamSubmission
  alias Tasky.Grading

  @doc """
  Dieselbe Musterlösung, aber für Teilnehmende statt für die Korrektur.

  Der einzige Unterschied ist das `;`: mehrere gültige Antworten werden zu
  `"pdf, .pdf"` aufgelöst (siehe `Tasky.Correction.AnswerVariants`). Das
  darf **nicht** in `sample_solution_doc/1` selbst passieren — daran hängen die
  Autokorrektur und die Editoren der Lehrperson, und beide brauchen das rohe
  Trennzeichen.
  """
  def sample_solution_doc_for_learner(%Exam{} = exam),
    do: exam |> Exams.sample_solution_doc() |> AnswerVariants.humanize_doc()

  @doc """
  Die Verdikte einer Abgabe, keyed by `answerId`, für die Anzeige bei Lernenden.

  `"correct"`, `"half"` oder `"wrong"` — dasselbe Vokabular, das
  `Tasky.Correction.SolutionHints` an den Antwortknoten schreibt. Manuell
  vergebene Teilpunkte werden dafür über `Grading.marker_verdict/2` aufgelöst,
  mit dem Blockmaximum aus `resolve_block_points/3`: derselbe Pfad, den auch
  `set_block_verdict/5` beim Setzen der ✅/🟡/❌ nimmt.

  `block_verdicts` ist die verbindliche Quelle. Der Textmarker im korrigierten
  Dokument dient nur als Rückfall für Blöcke, die noch aus einer Bulk-Korrektur
  stammen und deren Verdikt nie einzeln gespeichert wurde.
  """
  @spec learner_verdicts(Exam.t(), ExamSubmission.t()) :: %{String.t() => String.t()}
  def learner_verdicts(%Exam{} = exam, %ExamSubmission{} = submission) do
    exam
    |> judged_answers(submission)
    |> Map.new(fn {answer_id, verdict, block_max} ->
      {answer_id, Grading.marker_verdict(verdict, block_max)}
    end)
  end

  @doc """
  Die erreichten Punkte einer Abgabe pro Antwortfeld, keyed by `answerId`, als
  Anzeigetext — für Lernende, die am Feld die Punktzahl statt ✅/🟡/❌ sehen.
  Mit bekanntem Blockmaximum steht es dabei: `"1 / 2"`, sonst nur `"1.5"`.

  Ein 🟡 allein liest sich wie „ein halber Punkt", auch bei 1.5 von 2 Punkten;
  die Zahl sagt, was wirklich vergeben wurde. Gerechnet wird mit
  `Grading.awarded_points/2`, demselben Pfad wie die Gesamtpunktzahl.

  Ohne Blockmaximum (keine Punkte konfiguriert, oder ein Block mit 0 Punkten)
  gibt es für ein Wort-Verdikt keine Zahl: das Feld fehlt in der Map und behält
  sein Zeichen. Manuell vergebene Punkte sind selbst die Zahl.
  """
  @spec learner_points(Exam.t(), ExamSubmission.t()) :: %{String.t() => String.t()}
  def learner_points(%Exam{} = exam, %ExamSubmission{} = submission) do
    exam
    |> judged_answers(submission)
    |> Enum.reduce(%{}, fn {answer_id, verdict, block_max}, acc ->
      awarded = Grading.format_points(Grading.awarded_points(verdict, block_max))

      cond do
        is_number(block_max) and block_max > 0 ->
          Map.put(acc, answer_id, awarded <> " / " <> Grading.format_points(block_max))

        is_number(verdict) ->
          Map.put(acc, answer_id, awarded)

        true ->
          acc
      end
    end)
  end

  @doc """
  Die erreichten Punkte pro Frage, keyed by part id, als Anzeigetext `"2/4"` —
  für die Frage-Überschrift der zurückgegebenen Prüfung.

  Nur Fragen mit mehr als einem Antwortfeld: Bei einem einzigen Feld steht
  dieselbe Zahl schon am Feld. Gezählt wird, was in `points_per_part`
  gespeichert ist, also dieselbe Zahl, die in die Gesamtpunktzahl eingeht.
  Ohne Punkte der Frage oder ohne gespeicherte Punkte fehlt die Frage.
  """
  @spec learner_part_points(Exam.t(), ExamSubmission.t()) :: %{String.t() => String.t()}
  def learner_part_points(%Exam{answer_mode: "answer_fields"} = exam, %ExamSubmission{} = sub) do
    max_by_part = exam.sample_solution_points || %{}
    points_by_part = sub.points_per_part || %{}

    sub
    |> Exams.correction_content()
    |> ExamDoc.split_content_into_parts(exam.answer_mode)
    |> Enum.reduce(%{}, fn part, acc ->
      max = Map.get(max_by_part, part.id)
      points = Map.get(points_by_part, part.id)
      fields = length(NodePatcher.list_answer_blocks(part.nodes))

      if fields > 1 and is_number(max) and max > 0 and is_number(points) do
        Map.put(acc, part.id, Grading.format_points(points) <> "/" <> Grading.format_points(max))
      else
        acc
      end
    end)
  end

  def learner_part_points(%Exam{}, %ExamSubmission{}), do: %{}

  # `{answerId, verdict, block_max}` für jedes bewertete Antwortfeld, mit der
  # Quellen-Rangfolge aus `learner_verdicts/2`.
  defp judged_answers(exam, submission) do
    explicit = submission.block_verdicts || %{}

    submission
    |> Exams.correction_content()
    |> ExamDoc.split_content_into_parts(exam.answer_mode)
    |> Enum.flat_map(fn part ->
      blocks = NodePatcher.list_answer_blocks(part.nodes)
      points = Exams.resolve_block_points(exam, part.id, blocks)

      Enum.flat_map(blocks, &judged_answer(&1, explicit, points))
    end)
  end

  defp judged_answer(entry, explicit, points) do
    verdict = (entry.answer_id && Map.get(explicit, entry.answer_id)) || entry.inferred_verdict

    if is_binary(entry.answer_id) and not is_nil(verdict),
      do: [{entry.answer_id, verdict, points && Map.get(points, entry.index)}],
      else: []
  end

  @doc """
  Das zurückgegebene Dokument mit Verdikten und Musterlösung an den
  Antwortfeldern.

  `base_doc` ist, was die/der Lernende ohnehin zu sehen bekäme — die Korrektur
  der Lehrperson oder die eigenen Antworten. `verdicts` ist `learner_verdicts/2`
  oder `%{}`, wenn die Korrektur nicht freigegeben ist.

  Sobald Verdikte mitkommen, fallen die Textmarker ✅/🟡/❌ weg: das Verdikt hängt
  dann als Attribut am Knoten und wird vom Stylesheet gezeichnet. Stünden beide
  da, hätte jedes korrigierte Feld zwei Marker. Ohne Verdikte wird der Text
  nicht angefasst — dort gibt es keine Korrektur, und was die/der Lernende
  geschrieben hat, bleibt stehen.

  Optionen:

    * `:points` — `learner_points/2`; das Feld zeigt dann die Punktzahl statt
      des Zeichens. Default `%{}`.
    * `:part_points` — `learner_part_points/2`; die Frage-Überschrift bekommt
      sie als `points`-Attribut und zeigt sie darunter. Default `%{}`.
    * `:sample_solution` — `false`, wenn die Musterlösung nicht freigegeben ist:
      Verdikte und Punkte kommen trotzdem ans Feld, nur ohne Vorgabe darunter.
      Default `true`.
  """
  @spec return_doc_for_learner(Exam.t(), map() | nil, map(), keyword()) :: map()
  def return_doc_for_learner(%Exam{} = exam, base_doc, verdicts, opts \\ [])
      when is_map(verdicts) do
    base_doc = base_doc || %{}
    sample = if Keyword.get(opts, :sample_solution, true), do: exam.sample_solution

    base_doc
    |> strip_markers(verdicts)
    |> SolutionHints.annotate(sample, verdicts, Keyword.get(opts, :points, %{}))
    |> put_part_points(exam.answer_mode, Keyword.get(opts, :part_points, %{}))
  end

  defp put_part_points(doc, _mode, part_points) when map_size(part_points) == 0, do: doc

  defp put_part_points(doc, mode, part_points) do
    parts =
      doc
      |> ExamDoc.split_content_into_parts(mode)
      |> Enum.map(fn
        %{id: id, nodes: [heading | rest]} = part when is_map_key(part_points, id) ->
          attrs = Map.put(heading["attrs"] || %{}, "points", part_points[id])
          %{part | nodes: [Map.put(heading, "attrs", attrs) | rest]}

        part ->
          part
      end)

    Map.merge(
      doc,
      ExamDoc.assemble_parts_into_content(ExamDoc.content_preamble(doc, mode), parts)
    )
  end

  defp strip_markers(doc, verdicts) when map_size(verdicts) == 0, do: doc

  defp strip_markers(doc, _verdicts) do
    nodes = Map.get(doc, "content", []) || []
    Map.put(doc, "content", NodePatcher.rewrite_markers(nodes, %{}))
  end
end
