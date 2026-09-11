defmodule Tasky.GradingTest do
  use ExUnit.Case, async: true

  alias Tasky.Grading

  describe "round_quarter/1" do
    test "rounds to the nearest 0.25" do
      assert Grading.round_quarter(1.1) == 1.0
      assert Grading.round_quarter(1.13) == 1.25
      assert Grading.round_quarter(1.375) == 1.5
      assert Grading.round_quarter(0.0) == 0.0
    end

    test "any input lands on a 0.25 grid point" do
      for i <- 0..400 do
        n = i / 40
        rounded = Grading.round_quarter(n)
        assert Float.round(rounded * 4) == rounded * 4
        assert abs(rounded - n) <= 0.125 + 1.0e-9
      end
    end
  end

  describe "normalize_manual_points/2" do
    test "clamps to [0, block_max] and quarter-rounds" do
      assert Grading.normalize_manual_points(99, 2.0) == 2.0
      assert Grading.normalize_manual_points(-1, 2.0) == 0.0
      assert Grading.normalize_manual_points(0.3, 2.0) == 0.25
    end

    test "without a known max only the lower bound applies" do
      assert Grading.normalize_manual_points(99, nil) == 99.0
      assert Grading.normalize_manual_points(-5, nil) == 0.0
    end

    test "never exceeds an off-grid block max" do
      # Equal-split maxima are not on the 0.25 grid (2 points over 3 blocks).
      # Clamping before rounding let `round_quarter/1` push the value back
      # above the max: 0.7 → min(0.7, 0.666…) → 0.75.
      block_max = 2 / 3

      assert Grading.normalize_manual_points(0.7, block_max) == block_max
      refute Grading.normalize_manual_points(0.7, block_max) > block_max
    end

    test "a value at an off-grid max does not read as fully correct" do
      block_max = 2 / 3
      normalized = Grading.normalize_manual_points(0.6, block_max)

      assert normalized == 0.5
      assert Grading.marker_verdict(normalized, block_max) == "half"
    end
  end

  describe "awarded_points/2" do
    test "verdict vocabulary" do
      assert Grading.awarded_points("correct", 2.0) == 2.0
      assert Grading.awarded_points("half", 2.0) == 1.0
      assert Grading.awarded_points("wrong", 2.0) == 0
      assert Grading.awarded_points(1.25, 2.0) == 1.25
      assert Grading.awarded_points(nil, 2.0) == 0
    end

    test "unknown block max counts 0 for string verdicts" do
      assert Grading.awarded_points("correct", nil) == 0
    end
  end

  describe "marker_verdict/2" do
    test "maps numeric verdicts onto the marker vocabulary" do
      assert Grading.marker_verdict(0, 2.0) == "wrong"
      assert Grading.marker_verdict(2.0, 2.0) == "correct"
      assert Grading.marker_verdict(1.0, 2.0) == "half"
      assert Grading.marker_verdict("correct", 2.0) == "correct"
    end
  end

  describe "part_points/2" do
    test "nil when the part has no points configured" do
      assert Grading.part_points(%{0 => "correct"}, nil) == nil
    end

    test "sums awarded points and integerizes whole totals" do
      verdicts = %{0 => "correct", 1 => "wrong", 2 => "half", 3 => 0.75}
      points = %{0 => 2.0, 1 => 2.0, 2 => 1.0, 3 => 1.0}

      assert Grading.part_points(verdicts, points) == 3.25
      assert Grading.part_points(%{0 => "correct"}, %{0 => 2.0}) == 2
    end
  end

  describe "sum_points/1" do
    test "sums numeric values, ignores garbage, nil-safe" do
      assert Grading.sum_points(%{"a" => 1, "b" => 2.5, "c" => "x"}) == 3.5
      assert Grading.sum_points(nil) == 0
    end
  end

  describe "mark steps" do
    test "the pickable steps, coarsest first" do
      assert Grading.mark_steps() == ["0.25", "0.1"]
      assert Grading.default_mark_step() == "0.25"
    end

    test "mark_step?/1 is the whitelist for client params" do
      assert Grading.mark_step?("0.25")
      assert Grading.mark_step?("0.1")
      refute Grading.mark_step?("0.2")
      refute Grading.mark_step?("0,1")
      refute Grading.mark_step?(0.1)
      refute Grading.mark_step?(nil)
    end

    test "mark_step_size/1 is the delta for the +/- buttons" do
      assert Grading.mark_step_size("0.25") == 0.25
      assert Grading.mark_step_size("0.1") == 0.1
    end

    test "an unknown step raises rather than falling back" do
      # The nil fallback lives in Exams.mark_step/1 alone: a caller that
      # forgets to resolve the exam's step must fail loudly, not silently
      # grade on 0.25.
      assert_raise KeyError, fn -> Grading.round_mark(4.3, nil) end
      assert_raise KeyError, fn -> Grading.round_mark(4.3, "0.2") end
      assert_raise KeyError, fn -> Grading.mark(5, 10, nil) end
      assert_raise KeyError, fn -> Grading.normalize_mark(4.3, nil) end
    end
  end

  describe "round_mark/2" do
    test "takes integers too" do
      assert Grading.round_mark(5, "0.25") == 5.0
      assert Grading.round_mark(-3, "0.1") == -3.0
    end

    test "rounds to the step's grid" do
      assert Grading.round_mark(4.3, "0.25") == 4.25
      assert Grading.round_mark(4.3, "0.1") == 4.3
      assert Grading.round_mark(4.7, "0.25") == 4.75
      assert Grading.round_mark(4.7, "0.1") == 4.7
    end

    test "ties round away from zero, in the learner's favour" do
      assert Grading.round_mark(4.25, "0.1") == 4.3
      assert Grading.round_mark(4.75, "0.1") == 4.8
      assert Grading.round_mark(4.125, "0.25") == 4.25
    end

    test "any input lands exactly on the step's grid" do
      # Integer denominators keep this exact — no epsilon. Computing with the
      # float step instead would not: 43 * 0.1 == 4.300000000000001.
      for step <- Grading.mark_steps(), i <- 0..5000 do
        n = i / 1000
        d = round(1 / Grading.mark_step_size(step))
        m = Grading.round_mark(n, step)
        assert Float.round(m * d) == m * d
        assert abs(m - n) <= Grading.mark_step_size(step) / 2 + 1.0e-9
      end
    end
  end

  describe "mark/3" do
    test "Swiss 1-6 scale" do
      assert Grading.mark(0, 10, "0.25") == 1.0
      assert Grading.mark(10, 10, "0.25") == 6.0
      assert Grading.mark(5, 10, "0.25") == 3.5
    end

    test "one result, three grids" do
      assert Grading.mark(7.4, 10, "0.25") == 4.75
      assert Grading.mark(7.4, 10, "0.1") == 4.7
    end

    test "nil without max points, whatever the step" do
      for step <- Grading.mark_steps() do
        assert Grading.mark(5, nil, step) == nil
        assert Grading.mark(5, 0, step) == nil
      end
    end

    test "clamped to [1, 6] even for out-of-range points" do
      for step <- Grading.mark_steps() do
        assert Grading.mark(-5, 10, step) == 1.0
        assert Grading.mark(20, 10, step) == 6.0
      end
    end

    test "always on the step's grid within [1, 6]" do
      for step <- Grading.mark_steps(), max <- [7, 10, 12.5, 33, 60], points <- 0..60 do
        d = round(1 / Grading.mark_step_size(step))
        m = Grading.mark(points / 2, max, step)
        assert m >= 1.0 and m <= 6.0
        assert Float.round(m * d) == m * d
      end
    end
  end

  describe "normalize_mark/2" do
    test "rounds to the step and clamps to [1, 6]" do
      assert Grading.normalize_mark(4.3, "0.25") == 4.25
      assert Grading.normalize_mark(4.3, "0.1") == 4.3
      assert Grading.normalize_mark(4.7, "0.25") == 4.75
      assert Grading.normalize_mark(9.0, "0.1") == 6.0
      assert Grading.normalize_mark(-3, "0.1") == 1.0
    end

    test "absorbs the drift of a +/- step" do
      # 4.7 + 0.1 == 4.800000000000001 in binary floats.
      assert Grading.normalize_mark(4.7 + 0.1, "0.1") == 4.8
      assert Grading.normalize_mark(4.8 - 0.1, "0.1") == 4.7
    end
  end

  describe "the points grid is untouched by the mark step" do
    test "points rounding takes no step and stays on 0.25" do
      assert Grading.normalize_points(4.3) == 4.25
      assert Grading.round_quarter(4.3) == 4.25
      assert Grading.half_of(2.5) == 1.25
      assert Grading.normalize_manual_points(0.3, 2.0) == 0.25
    end
  end

  describe "formatting" do
    test "format_mark" do
      assert Grading.format_mark(4.0) == "4.0"
      assert Grading.format_mark(4.25) == "4.25"
      assert Grading.format_mark(4.5) == "4.5"
      assert Grading.format_mark(4.7) == "4.7"
      assert Grading.format_mark(nil) == "—"
      assert Grading.format_mark(nil, "") == ""
    end

    test "format_mark uses as few decimals as the value needs" do
      # Both regressions the step-independent formatter has to avoid: the old
      # `decimals: 2` branch printed a tenth as "4.10", and trimming the
      # trailing zeros off it turns 4.0 into "4.".
      refute Grading.format_mark(4.1) == "4.10"
      assert Grading.format_mark(4.1) == "4.1"
      refute Grading.format_mark(4.0) == "4."
      assert Grading.format_mark(6.0) == "6.0"
      assert Grading.format_mark(1.0) == "1.0"
    end

    test "every grid point survives the round trip through the number input" do
      for step <- Grading.mark_steps(),
          i <- 0..round(5 / Grading.mark_step_size(step)) do
        m = Grading.normalize_mark(1.0 + i * Grading.mark_step_size(step), step)
        assert {^m, ""} = m |> Grading.format_mark() |> Float.parse()
      end
    end

    test "format_points" do
      assert Grading.format_points(3) == "3"
      assert Grading.format_points(3.0) == "3"
      assert Grading.format_points(1.5) == "1.5"
      assert Grading.format_points(0.25) == "0.25"
      assert Grading.format_points(nil) == "—"
    end

    test "parse_points" do
      assert Grading.parse_points("1,5") == 1.5
      assert Grading.parse_points("2") == 2
      assert Grading.parse_points(" 0.25 ") == 0.25
      assert Grading.parse_points("abc") == nil
      assert Grading.parse_points(1.25) == 1.25
    end
  end
end
