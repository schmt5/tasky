defmodule Tasky.Correction.CheckboxPatterns do
  @moduledoc """
  Regroups the checkboxes of one list by answer pattern for the grouped
  correction view: everyone who ticked exactly A and C lands in one pattern,
  whatever the others did.

  The input is the checkbox blocks of one list as `Tasky.Exams.list_part_answer_groups/2`
  returns them — one block per checkbox, grouped by tick. Verdicts stay per
  checkbox; a pattern is a view onto them, so auto-correction, part points and
  the per-submission correction are untouched by it.

  Each pattern:

      %{
        key: "101",                 # one char per checkbox: 1 ticked, 0 not, - missing
        count: 14,
        students: [%{submission_id, firstname, lastname}, ...],
        options: [%{index, label, state, expected, deviation, verdict, default_verdict, max_points}, ...],
        matches_solution?: true,
        verdict: "correct" | "wrong" | :partial,
        points: 2 | nil,            # nil when a checkbox has no points or mixed verdicts
        max_points: 2 | nil
      }

  An option's `state` is `:checked`, `:unchecked` or `:missing` (the student
  never opened the exam), `expected` is `true`/`false`/`nil` (no solution), and
  `deviation` is `:extra` (ticked, should not be), `:missing` (should be ticked,
  is not) or `nil`. Its `verdict` is the shared explicit verdict of the pattern's
  students, the system's default when nobody was judged yet, or `:mixed` when
  the students of one pattern were judged differently in the per-student view.
  """

  alias Tasky.Grading

  @checked "angekreuzt"
  @unchecked "nicht angekreuzt"

  def build(blocks) when is_list(blocks) do
    cells = cells_by_submission(blocks)

    cells
    |> Enum.group_by(fn {_id, %{by_index: by_index}} -> pattern_key(blocks, by_index) end)
    |> Enum.map(fn {key, members} -> build_pattern(key, members, blocks) end)
    |> Enum.sort_by(&{-&1.count, &1.key})
  end

  # %{submission_id => %{student: ..., by_index: %{index => {state, verdict}}}}
  defp cells_by_submission(blocks) do
    for block <- blocks, group <- block.groups, student <- group.students, reduce: %{} do
      acc ->
        cell = {state(group.text), student[:verdict]}

        Map.update(
          acc,
          student.submission_id,
          %{student: Map.delete(student, :verdict), by_index: %{block.index => cell}},
          &put_in(&1, [:by_index, block.index], cell)
        )
    end
  end

  defp state(@checked), do: :checked
  defp state(@unchecked), do: :unchecked
  defp state(_none), do: :missing

  defp pattern_key(blocks, by_index) do
    Enum.map_join(blocks, fn block ->
      case Map.get(by_index, block.index) do
        {:checked, _} -> "1"
        {:unchecked, _} -> "0"
        _ -> "-"
      end
    end)
  end

  defp build_pattern(key, members, blocks) do
    options = Enum.map(blocks, &build_option(&1, members))

    %{
      key: key,
      count: length(members),
      students:
        members
        |> Enum.map(fn {_id, %{student: student}} -> student end)
        |> Enum.sort_by(&{&1.lastname || "", &1.firstname || ""}),
      options: options,
      matches_solution?: Enum.all?(options, &(&1.expected != nil and &1.deviation == nil)),
      verdict: pattern_verdict(options),
      points: awarded_points(options),
      max_points: max_points(options)
    }
  end

  defp build_option(block, members) do
    {state, verdicts} =
      Enum.reduce(members, {:missing, []}, fn {_id, %{by_index: by_index}}, {_s, vs} ->
        case Map.get(by_index, block.index) do
          {state, verdict} -> {state, [verdict | vs]}
          nil -> {:missing, [nil | vs]}
        end
      end)

    expected = expected(block.sample_answers)

    %{
      index: block.index,
      label: block.label,
      state: state,
      expected: expected,
      deviation: deviation(state, expected),
      verdict: option_verdict(Enum.uniq(verdicts), default_verdict(block, state)),
      default_verdict: default_verdict(block, state),
      max_points: block.max_points
    }
  end

  defp expected([@checked]), do: true
  defp expected([@unchecked]), do: false
  defp expected(_none), do: nil

  defp deviation(_state, nil), do: nil
  defp deviation(:checked, false), do: :extra
  defp deviation(state, true) when state != :checked, do: :missing
  defp deviation(_state, _expected), do: nil

  # The default of the tick group this pattern's students sit in.
  defp default_verdict(block, state) do
    text =
      case state do
        :checked -> @checked
        :unchecked -> @unchecked
        :missing -> nil
      end

    case Enum.find(block.groups, &(&1.text == text)) do
      %{default_verdict: v} -> v
      nil -> "wrong"
    end
  end

  defp option_verdict([nil], default), do: default
  defp option_verdict([v], _default), do: v
  defp option_verdict(_mixed, _default), do: :mixed

  defp pattern_verdict(options) do
    cond do
      Enum.all?(options, &(&1.verdict == "correct")) -> "correct"
      Enum.all?(options, &(&1.verdict == "wrong")) -> "wrong"
      true -> :partial
    end
  end

  defp awarded_points(options) do
    if Enum.all?(options, &(is_number(&1.max_points) and &1.verdict != :mixed)) do
      options
      |> Enum.map(&Grading.awarded_points(&1.verdict, &1.max_points))
      |> Enum.sum()
      |> Grading.normalize_points()
    end
  end

  defp max_points(options) do
    if Enum.all?(options, &is_number(&1.max_points)) do
      options |> Enum.map(& &1.max_points) |> Enum.sum() |> Grading.normalize_points()
    end
  end
end
