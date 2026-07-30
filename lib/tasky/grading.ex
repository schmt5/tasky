defmodule Tasky.Grading do
  @moduledoc """
  Pure grading domain: quarter-point rounding, verdict semantics, part/total
  computation and the Swiss mark formula.

  This is the single source of truth — the correction LiveViews, the grading
  overview, the PDF print view and the auto-correction pipeline all derive
  their numbers from here. Everything is a pure function over plain values.

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

  @doc "Rounds to the nearest 0.25."
  def round_quarter(n) when is_number(n), do: Float.round(n * 4.0) / 4

  @doc """
  Normalizes a manual points verdict: non-negative, clamped to the block's
  max points (when known), rounded to 0.25 steps.
  """
  def normalize_manual_points(points, block_max) when is_number(points) do
    points
    |> max(0)
    |> then(&if is_number(block_max), do: min(&1, block_max), else: &1)
    |> round_quarter()
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

  ## Swiss mark

  @doc """
  The Swiss 1–6 mark: 0 points → 1, max points → 6, linear in between,
  rounded to the nearest 0.25 and clamped to [1.0, 6.0]. Returns `nil` when
  no max points are configured.
  """
  def mark(_points, max) when max in [nil, 0, 0.0], do: nil

  def mark(points, max) when is_number(points) and is_number(max) do
    (points / max * 5 + 1)
    |> round_quarter()
    |> clamp_mark()
  end

  def mark(_, _), do: nil

  @doc "Quarter-rounds a points value; whole numbers come back as integers."
  def normalize_points(n) when is_number(n), do: n |> round_quarter() |> integerize()

  @doc "Half of the block's max points, on the 0.25 grid; 0 when max is unknown."
  def half_of(max) when is_number(max), do: round_quarter(max * 0.5)
  def half_of(_), do: 0

  @doc "Normalizes a manually entered mark: quarter-rounded, clamped to [1, 6]."
  def normalize_mark(n) when is_number(n), do: n |> round_quarter() |> clamp_mark()

  defp clamp_mark(n) when n < @mark_min, do: @mark_min
  defp clamp_mark(n) when n > @mark_max, do: @mark_max
  defp clamp_mark(n), do: n

  ## Formatting / parsing (shared by screen and PDF)

  @doc ~S|Formats a mark: whole numbers as "4.0", quarters as "4.25"; nil → placeholder.|
  def format_mark(n, placeholder \\ "—")
  def format_mark(nil, placeholder), do: placeholder

  def format_mark(n, _placeholder) when is_number(n) do
    n = n * 1.0

    if n == trunc(n),
      do: :erlang.float_to_binary(n, decimals: 1),
      else: :erlang.float_to_binary(n, decimals: 2)
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

  defp points_value(n) when is_number(n), do: n
  defp points_value(_), do: 0

  defp integerize(n) when is_float(n) do
    if n == trunc(n), do: trunc(n), else: n
  end

  defp integerize(n), do: n
end
