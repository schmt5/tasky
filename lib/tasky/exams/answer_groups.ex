defmodule Tasky.Exams.AnswerGroups do
  @moduledoc """
  The grouped correction ("Korrektur nach Frage"): every learner's answer
  to one part, grouped by identical text, with the system's default verdict
  and the nearest sample answer. Read-only; called through the `Tasky.Exams`
  facade.
  """

  alias Tasky.AI.NodePatcher
  alias Tasky.Correction.AnswerVariants
  alias Tasky.Correction.StringComparator
  alias Tasky.ExamDoc
  alias Tasky.Exams
  alias Tasky.Exams.Exam

  @doc """
  Groups the answers given by every submission to a single part, one group per
  unique answer text, paired with the system's pre-judged verdict against the
  sample solution and the teacher's current verdict (if any).

  Returns a list of `%{index, type, group, label, max_points, sample_answers,
  groups}` — one entry per answer-bearing block in the part, in document
  order. `max_points` is the block's share resolved via
  `resolve_block_points/3` (`nil` when the part has no points configured).

  A checkbox (`type: "taskItem"`) is grouped by its tick, not by its text:
  the group texts are `"angekreuzt"` and `"nicht angekreuzt"`, `label` is the
  checkbox's own label, and `group` names the checkbox list it belongs to
  (see `Tasky.AI.NodePatcher.list_answer_blocks/1`). Within `groups`:

      %{
        text: "fliegen" | nil,            # nil = "no answer"
        count: 18,
        students: [%{submission_id, firstname, lastname, verdict}, ...],
        default_verdict: "correct" | "wrong",
        current_verdict: "correct" | "half" | "wrong" | number | nil | :mixed,
        diff: [{:eq | :ins | :del, string}, ...],
        nearest_sample: "fliegen" | nil
      }

  `current_verdict` is `nil` when no submission in the group has an explicit
  teacher verdict, `:mixed` when submissions disagree, otherwise the shared
  value. `default_verdict` honors the part's text comparison options
  (`ignore_case`, `ignore_spelling`, `ignore_punctuation`), using the same matcher (`Tasky.Correction.StringComparator.text_match?/3`)
  as auto-correction.
  """
  def list_part_answer_groups(%Exam{} = exam, part_id) when is_binary(part_id) do
    part_cfg = Map.get(exam.ai_correction_config || %{}, part_id, %{})
    sample_part = find_part(Exams.sample_solution_doc(exam), exam.answer_mode, part_id)
    exam_part = find_part(exam.content || %{}, exam.answer_mode, part_id)
    sample_blocks = answer_blocks(sample_part)
    exam_blocks = if exam_part, do: answer_blocks(exam_part), else: sample_blocks

    context = %{
      opts: StringComparator.match_opts(part_cfg),
      labels_by_index: if(exam_part, do: ExamDoc.answer_block_labels(exam_part.nodes), else: %{}),
      sample_block_by_index: Map.new(sample_blocks, &{&1.index, &1}),
      points_by_index: Exams.resolve_block_points(exam, part_id, exam_blocks),
      per_submission_blocks:
        Enum.map(Exams.list_exam_submissions(exam), fn sub ->
          part = find_part(Exams.correction_content(sub), exam.answer_mode, part_id)
          {sub, answer_blocks(part)}
        end)
    }

    Enum.map(exam_blocks, &block_groups(&1, context))
  end

  defp find_part(doc, answer_mode, part_id) do
    doc
    |> ExamDoc.split_content_into_parts(answer_mode)
    |> Enum.find(&(&1.id == part_id))
  end

  defp answer_blocks(nil), do: []
  defp answer_blocks(part), do: NodePatcher.list_answer_blocks(part.nodes)

  # A radio group is grouped by the chosen option's label, compared exactly: an
  # option is picked, not typed, so no text options and no `;` alternatives (a
  # `;` in a label must not split it).
  defp block_groups(%{type: "choice", index: index} = block, context) do
    sample_answers =
      case Map.get(context.sample_block_by_index, index) do
        %{text: label} when label != "" -> [label]
        _ -> []
      end

    block
    |> group_base(context, Map.get(context.labels_by_index, index), sample_answers)
    |> put_groups(context, &normalize_group_text(&1.text), %{})
  end

  # A checkbox's label is the same for everyone; what differs is the tick.
  # Grouping by the label put the whole class in one "correct" group, ticked
  # or not.
  defp block_groups(%{type: "taskItem", index: index} = block, context) do
    sample_answers =
      case Map.get(context.sample_block_by_index, index) do
        %{checked: checked} -> [checkbox_state_text(checked)]
        nil -> []
      end

    block
    |> group_base(context, block.text, sample_answers)
    |> put_groups(context, &checkbox_state_text(&1.checked), %{})
  end

  defp block_groups(%{index: index} = block, context) do
    sample_text = context.sample_block_by_index |> Map.get(index, %{}) |> Map.get(:text)

    block
    |> group_base(
      context,
      Map.get(context.labels_by_index, index),
      AnswerVariants.split(sample_text)
    )
    |> put_groups(context, &normalize_group_text(&1.text), context.opts)
  end

  defp group_base(%{index: index} = block, context, label, sample_answers) do
    %{
      index: index,
      type: block.type,
      group: block[:group],
      max_points: context.points_by_index && Map.get(context.points_by_index, index),
      label: label,
      sample_answers: sample_answers
    }
  end

  defp put_groups(entry, context, key_fun, opts) do
    groups =
      build_answer_groups(
        context.per_submission_blocks,
        entry.index,
        key_fun,
        entry.sample_answers,
        opts
      )

    Map.put(entry, :groups, groups)
  end

  # The group text of a checkbox answer — also what the teacher sees.
  defp checkbox_state_text(true), do: "angekreuzt"
  defp checkbox_state_text(_unchecked), do: "nicht angekreuzt"

  defp build_answer_groups(per_submission_blocks, index, key_fun, sample_answers, opts) do
    entries =
      Enum.map(per_submission_blocks, fn {sub, blocks} ->
        case Enum.find(blocks, &(&1.index == index)) do
          nil -> {sub, nil, nil}
          %{answer_id: id} = block -> {sub, key_fun.(block), id}
        end
      end)

    entries
    |> Enum.group_by(fn {_sub, text, _id} -> text end)
    |> Enum.map(fn {text, members} ->
      subs_with_ids = Enum.map(members, fn {sub, _text, id} -> {sub, id} end)
      build_one_group(text, subs_with_ids, sample_answers, opts)
    end)
    |> Enum.sort_by(fn g -> -g.count end)
  end

  defp build_one_group(text, subs_with_ids, sample_answers, opts) do
    subs = Enum.map(subs_with_ids, fn {sub, _id} -> sub end)

    # Verdicts are keyed by each submission's own block answerId.
    verdicts =
      Enum.map(subs_with_ids, fn {s, answer_id} ->
        answer_id && Map.get(s.block_verdicts || %{}, answer_id)
      end)

    current_verdict =
      case Enum.uniq(verdicts) do
        [v] -> v
        _ -> :mixed
      end

    default_verdict = default_group_verdict(text, sample_answers, opts)
    nearest = nearest_sample(text, sample_answers)
    diff = diff_against(text, nearest)

    # `verdict` is this student's own explicit verdict for the block (nil =
    # none). The checkbox patterns regroup students across blocks and need it
    # per person, not just the group's shared value.
    students =
      Enum.zip_with(subs, verdicts, fn s, verdict ->
        %{submission_id: s.id, firstname: s.firstname, lastname: s.lastname, verdict: verdict}
      end)

    %{
      text: text,
      count: length(subs),
      students: students,
      default_verdict: default_verdict,
      current_verdict: current_verdict,
      diff: diff,
      nearest_sample: nearest
    }
  end

  defp normalize_group_text(nil), do: nil

  defp normalize_group_text(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      t -> t
    end
  end

  defp default_group_verdict(nil, _samples, _opts), do: "wrong"
  defp default_group_verdict(_text, [], _opts), do: "wrong"

  defp default_group_verdict(text, samples, opts) do
    trimmed = String.trim(text)

    if trimmed != "" and
         Enum.any?(samples, &StringComparator.text_match?(trimmed, &1, opts)),
       do: "correct",
       else: "wrong"
  end

  defp nearest_sample(nil, _), do: nil
  defp nearest_sample(_text, []), do: nil

  defp nearest_sample(_text, [single]), do: single

  defp nearest_sample(text, samples) do
    lower = String.downcase(text)

    Enum.max_by(samples, fn s ->
      String.jaro_distance(lower, String.downcase(s))
    end)
  end

  defp diff_against(nil, _), do: []
  defp diff_against(text, nil), do: [{:eq, text}]
  defp diff_against(text, sample), do: String.myers_difference(text, sample)
end
