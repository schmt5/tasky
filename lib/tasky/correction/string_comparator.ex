defmodule Tasky.Correction.StringComparator do
  @moduledoc """
  Deterministic, AI-free correction of a single exam part.

  Returns `{:ok, %{verdicts:, points:}}` — the contract the bulk runner
  consumes, kept implementation-agnostic so a future AI-backed corrector
  could be swapped in without further changes.

  Comparison rules per answer node:

  * `taskItem`     — `attrs["checked"]` boolean equality (ignores text options).
  * `answerBlock`  — text comparison; sample text may list alternative
                     accepted answers separated by `;`. Trimmed.
  * `lueckentext`  — same as `answerBlock`.

  Per-part options (`opts`):

  * `:ignore_case`     — lowercase both sides before comparing.
  * `:ignore_spelling` — fuzzy match via `String.jaro_distance/2 >= 0.85`
                         (fallback to exact match for very short strings).
  * `:block_points`    — optional `%{index => points}` map (zero-based block
                         index, as from `Tasky.Exams.resolve_block_points/3`).
                         When present, each correct block contributes its own
                         points (supports unequal distributions).

  Points: sum of correct blocks' points (or, without `:block_points`,
  `correct_count / total_count * max_points`), rounded to 0.25.
  """

  @answer_types ["answerBlock", "lueckentext", "taskItem"]
  @fuzzy_threshold 0.85
  @fuzzy_min_length 4

  @doc """
  Returns `{:ok, %{verdicts: %{"id" => "correct" | "incorrect"}, points: number}}`.

  `annotated_submission_nodes` must have already been annotated by
  `Tasky.AI.NodePatcher.annotate/1` (each answer node carries
  `attrs["__ai_id"]`).
  """
  def correct_part(annotated_submission_nodes, sample_solution_nodes, max_points, opts \\ %{})
      when is_list(annotated_submission_nodes) and is_list(sample_solution_nodes) do
    submission_answers = collect_answers(annotated_submission_nodes)
    sample_answers = collect_answers(sample_solution_nodes)

    verdicts =
      submission_answers
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {sub, idx}, acc ->
        sample = Enum.at(sample_answers, idx)
        verdict = verdict_for(sub, sample, opts)

        case sub.id do
          nil -> acc
          id -> Map.put(acc, id, verdict)
        end
      end)

    points = calculate_points(verdicts, max_points, opts)

    {:ok, %{verdicts: verdicts, points: points}}
  end

  defp verdict_for(_sub, nil, _opts), do: "incorrect"

  defp verdict_for(%{type: "taskItem", checked: s}, %{type: "taskItem", checked: t}, _opts) do
    if s == t, do: "correct", else: "incorrect"
  end

  defp verdict_for(%{type: type, text: student}, %{type: type, text: sample_text}, opts)
       when type in ["answerBlock", "lueckentext"] do
    student_trimmed = String.trim(student || "")

    if student_trimmed == "" do
      "incorrect"
    else
      accepted =
        (sample_text || "")
        |> String.split(";")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      if Enum.any?(accepted, &text_match?(student_trimmed, &1, opts)),
        do: "correct",
        else: "incorrect"
    end
  end

  defp verdict_for(_sub, _sample, _opts), do: "incorrect"

  @doc """
  Returns true if a single `student` answer matches a single `accepted`
  alternative under `opts` (`:ignore_case`, `:ignore_spelling`). Exposed so the
  bulk-correction grouping in `Tasky.Exams` derives its default verdicts with
  exactly the same rule as auto-correction.
  """
  def text_match?(student, accepted, opts) do
    s = normalize(student, opts)
    a = normalize(accepted, opts)

    cond do
      s == a ->
        true

      Map.get(opts, :ignore_spelling, false) and
        String.length(s) >= @fuzzy_min_length and
          String.length(a) >= @fuzzy_min_length ->
        String.jaro_distance(s, a) >= @fuzzy_threshold

      true ->
        false
    end
  end

  defp normalize(text, opts) do
    text = String.trim(text)
    if Map.get(opts, :ignore_case, false), do: String.downcase(text), else: text
  end

  # The `__ai_id` assigned by NodePatcher.annotate/1 is always `index + 1`,
  # so a block's points are looked up at `id - 1` in the :block_points map.
  defp calculate_points(verdicts, _max_points, %{block_points: bp})
       when is_map(bp) and map_size(bp) > 0 do
    raw =
      Enum.reduce(verdicts, 0.0, fn
        {id, "correct"}, acc -> acc + (Map.get(bp, String.to_integer(id) - 1) || 0)
        _, acc -> acc
      end)

    Tasky.Grading.round_quarter(raw)
  end

  defp calculate_points(verdicts, max_points, _opts), do: calculate_points(verdicts, max_points)

  defp calculate_points(_verdicts, nil), do: 0
  defp calculate_points(_verdicts, 0), do: 0

  defp calculate_points(verdicts, max_points) when is_number(max_points) do
    total = map_size(verdicts)

    if total == 0 do
      0
    else
      correct = verdicts |> Map.values() |> Enum.count(&(&1 == "correct"))
      raw = correct / total * max_points
      Tasky.Grading.round_quarter(raw)
    end
  end

  # --- Tree walking ---------------------------------------------------------

  defp collect_answers(nodes) when is_list(nodes) do
    nodes |> walk([]) |> Enum.reverse()
  end

  defp walk(nodes, acc) when is_list(nodes) do
    Enum.reduce(nodes, acc, &visit/2)
  end

  defp visit(%{"type" => type} = node, acc) when type in @answer_types do
    [build_entry(node) | acc]
  end

  defp visit(%{"content" => content}, acc) when is_list(content) do
    walk(content, acc)
  end

  defp visit(_, acc), do: acc

  defp build_entry(%{"type" => "taskItem"} = node) do
    %{
      type: "taskItem",
      id: get_in(node, ["attrs", "__ai_id"]),
      checked: get_in(node, ["attrs", "checked"]) == true
    }
  end

  defp build_entry(%{"type" => type} = node) when type in ["answerBlock", "lueckentext"] do
    %{
      type: type,
      id: get_in(node, ["attrs", "__ai_id"]),
      text: extract_plain_text(Map.get(node, "content", []))
    }
  end

  defp extract_plain_text(content) when is_list(content) do
    Enum.map_join(content, "", fn
      %{"type" => "text", "text" => t} -> t
      %{"content" => inner} when is_list(inner) -> extract_plain_text(inner)
      _ -> ""
    end)
  end

  defp extract_plain_text(_), do: ""
end
