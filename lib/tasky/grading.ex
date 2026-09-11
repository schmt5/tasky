defmodule Tasky.Grading do
  @moduledoc """
  Pure grading domain: rounding, verdict semantics, part/total computation
  and the Swiss mark formula.

  This is the single source of truth — the correction LiveViews, the grading
  overview, the PDF print view and the auto-correction pipeline all derive
  their numbers from here. Everything is a pure function over plain values.

  ## Two grids

  There are two independent rounding grids, and they must not be confused:

    * **Points** — always 0.25, for every exam. `round_quarter/1` and
      everything built on it (`normalize_manual_points/2`, `part_points/2`,
      `normalize_points/1`, `half_of/1`).
    * **Marks** — per exam, one of `mark_steps/0`. `round_mark/2` and
      everything built on it (`mark/3`, `normalize_mark/2`). The step comes
      from `exams.mark_step`; resolve it through `Exams.mark_step/1`, which
      is the one place the `nil` fallback lives.

  A mark is a pure function of points, max points and the step, so the step
  can be chosen (and changed) long after the points are in.

  ## Verdicts

  A block verdict is one of:

    * `"correct"` — full block points
    * `"half"` — half block points (legacy; still readable, no longer written)
    * `"wrong"` — zero points
    * a number — manual points, clamped to `[0, block_max]` in 0.25 steps
    * `nil` — no verdict

  """

  @mark_min 1.0
  @mark_max 6.0

  ## Rounding

  @doc """
  Rounds to the nearest 0.25 — the **points** grid.

  Unrelated to the exam's mark step: points are 0.25 everywhere, always.
  For marks use `round_mark/2`.
  """
  def round_quarter(n) when is_number(n), do: Float.round(n * 4.0) / 4

  @doc """
  Normalizes a manual points verdict: non-negative, rounded to 0.25 steps, then
  clamped to the block's max points (when known).

  Rounding must happen *before* the clamp. Equal-split block maxima are not on
  the 0.25 grid (2 points over 3 blocks → 0.666…), so clamping first lets
  `round_quarter/1` push the value back above the max — and a 0.75 on a 0.666
  block then reads as `"correct"`, putting a ✅ on a partly wrong answer.
  """
  def normalize_manual_points(points, block_max) when is_number(points) do
    points
    |> max(0)
    |> round_quarter()
    |> then(&if is_number(block_max), do: min(&1, block_max), else: &1)
  end

  ## Verdict semantics

  @doc "The verdict that counts: the teacher's explicit choice, else the inferred one."
  def effective_verdict(explicit, inferred), do: explicit || inferred

  @doc """
  Points a single verdict awards, given the block's max points.
  `nil` verdicts award 0.
  """
  def awarded_points("correct", block_max), do: points_value(block_max)
  def awarded_points("half", block_max), do: points_value(block_max) * 0.5
  def awarded_points("wrong", _block_max), do: 0
  def awarded_points(v, _block_max) when is_number(v), do: v
  def awarded_points(_other, _block_max), do: 0

  @doc """
  Maps a verdict to the marker vocabulary (✅/🟡/❌ ⇒ correct/half/wrong):
  full block points → `"correct"`, zero → `"wrong"`, anything between →
  `"half"`. String verdicts pass through.
  """
  def marker_verdict(v, block_max) when is_number(v) do
    cond do
      v == 0 -> "wrong"
      is_number(block_max) and v >= block_max -> "correct"
      true -> "half"
    end
  end

  def marker_verdict(v, _block_max), do: v

  ## Part / total computation

  @doc """
  Total points of one part from its effective verdicts and per-block max
  points (both keyed by block index). Returns `nil` when the part has no
  points configured (`points_by_index` is nil); whole numbers come back as
  integers.
  """
  def part_points(_verdicts_by_index, nil), do: nil

  def part_points(verdicts_by_index, points_by_index) when is_map(points_by_index) do
    verdicts_by_index
    |> Enum.reduce(0.0, fn {idx, verdict}, acc ->
      acc + awarded_points(verdict, points_by_index[idx])
    end)
    |> round_quarter()
    |> integerize()
  end

  @doc "Sums the numeric values of a points map (nil-safe); non-numbers count 0."
  def sum_points(nil), do: 0

  def sum_points(map) when is_map(map) do
    Enum.reduce(map, 0, fn
      {_k, v}, acc when is_number(v) -> acc + v
      _, acc -> acc
    end)
  end

  ## Mark grid

  # Stored as the string the teacher picked, because that string is also
  # literally the HTML `step=` attribute. The value is the integer
  # denominator: rounding goes through `Float.round(n * d) / d` with an
  # *integer* d, which lands exactly on the grid for every input. Computing
  # with the float step instead (`round(n / 0.1) * 0.1`) does not —
  # `43 * 0.1 == 4.300000000000001`.
  @mark_steps %{"0.25" => 4, "0.1" => 10}
  @mark_step_order ["0.25", "0.1"]
  @default_mark_step "0.25"

  @doc "The mark steps a teacher can pick, coarsest first."
  def mark_steps, do: @mark_step_order

  @doc "The step an exam falls back to before the teacher has chosen one."
  def default_mark_step, do: @default_mark_step

  @doc "True for a value that is one of `mark_steps/0`."
  def mark_step?(step), do: is_map_key(@mark_steps, step)

  @doc ~S|The step as a number, for the ± buttons: `"0.1"` → `0.1`.|
  def mark_step_size(step), do: 1 / denominator!(step)

  @doc """
  Rounds to the nearest grid point of `step` — the **mark** grid.

  Ties round away from zero, so on the 0.1 grid a 4.25 becomes 4.3: in the
  learner's favour, which is the defensible direction for a mark.

  Raises for an unknown step. The `nil` fallback is deliberately *not* here —
  it lives in `Exams.mark_step/1` alone, so a caller that forgets to resolve
  the exam's step fails loudly instead of silently grading on 0.25.
  """
  def round_mark(n, step) when is_number(n) do
    d = denominator!(step)
    # `n * 1.0` first: an integer mark (a teacher typing "5") would otherwise
    # make `n * d` an integer, and Float.round/2 only takes floats.
    Float.round(n * 1.0 * d) / d
  end

  ## Swiss mark

  @doc """
  The Swiss 1–6 mark: 0 points → 1, max points → 6, linear in between,
  rounded to `step`'s grid and clamped to [1.0, 6.0]. Returns `nil` when no
  max points are configured.

  The step is required. There is no arity-2 default: this formula once
  existed twice with different rounding and the PDF printed a different mark
  than the screen (`docs/ROBUSTNESS_PLAN.md`). A defaulting wrapper is how
  one caller quietly keeps the wrong grid — so every caller passes the
  exam's step, resolved through `Exams.mark_step/1`.
  """
  def mark(_points, max, _step) when max in [nil, 0, 0.0], do: nil

  def mark(points, max, step) when is_number(points) and is_number(max) do
    (points / max * 5 + 1)
    |> round_mark(step)
    |> clamp_mark()
  end

  def mark(_, _, _), do: nil

  @doc "Quarter-rounds a points value; whole numbers come back as integers."
  def normalize_points(n) when is_number(n), do: n |> round_quarter() |> integerize()

  @doc "Half of the block's max points, on the 0.25 grid; 0 when max is unknown."
  def half_of(max) when is_number(max), do: round_quarter(max * 0.5)
  def half_of(_), do: 0

  @doc "Normalizes a manually entered mark: rounded to `step`, clamped to [1, 6]."
  def normalize_mark(n, step) when is_number(n), do: n |> round_mark(step) |> clamp_mark()

  defp clamp_mark(n) when n < @mark_min, do: @mark_min
  defp clamp_mark(n) when n > @mark_max, do: @mark_max
  defp clamp_mark(n), do: n

  ## Formatting / parsing (shared by screen and PDF)

  @doc ~S"""
  Formats a mark with as few decimals as the value needs, but never fewer
  than one: `4.0`, `4.5`, `4.7`, `4.25`; nil → placeholder.

  Step-independent on purpose — the formatter never has to be told which
  grid the mark came from, so it cannot drift out of sync with one. Note
  that string-trimming the trailing zeros off `decimals: 2` is not an option:
  it turns 4.0 into `"4."`.
  """
  def format_mark(n, placeholder \\ "—")
  def format_mark(nil, placeholder), do: placeholder

  def format_mark(n, _placeholder) when is_number(n) do
    n = n * 1.0

    cond do
      n == trunc(n) -> :erlang.float_to_binary(n, decimals: 1)
      Float.round(n * 10) == n * 10 -> :erlang.float_to_binary(n, decimals: 1)
      true -> :erlang.float_to_binary(n, decimals: 2)
    end
  end

  @doc ~S|Formats points compactly: integers without decimals, "1.5", "0.25"; nil → placeholder.|
  def format_points(n, placeholder \\ "—")
  def format_points(nil, placeholder), do: placeholder
  def format_points(n, _placeholder) when is_integer(n), do: Integer.to_string(n)

  def format_points(n, _placeholder) when is_float(n) do
    if n == trunc(n) do
      Integer.to_string(trunc(n))
    else
      n |> :erlang.float_to_binary(decimals: 2) |> String.trim_trailing("0")
    end
  end

  @doc """
  Parses user-entered points ("1,5" or "1.5"); returns a number or nil.
  Accepts numbers as-is.
  """
  def parse_points(n) when is_number(n), do: n

  def parse_points(raw) when is_binary(raw) do
    case raw |> String.trim() |> String.replace(",", ".") |> Float.parse() do
      {n, ""} -> integerize(n)
      _ -> nil
    end
  end

  def parse_points(_), do: nil

  defp denominator!(step), do: Map.fetch!(@mark_steps, step)

  defp points_value(n) when is_number(n), do: n
  defp points_value(_), do: 0

  # Only ever called with `round_quarter/1` output or `Float.parse/1` output,
  # both of which are floats — a catch-all clause here would be unreachable.
  defp integerize(n) when is_float(n) do
    if n == trunc(n), do: trunc(n), else: n
  end
end
