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

  describe "mark/2" do
    test "Swiss 1-6 scale" do
      assert Grading.mark(0, 10) == 1.0
      assert Grading.mark(10, 10) == 6.0
      assert Grading.mark(5, 10) == 3.5
    end

    test "nil without max points" do
      assert Grading.mark(5, nil) == nil
      assert Grading.mark(5, 0) == nil
    end

    test "clamped to [1, 6] even for out-of-range points" do
      assert Grading.mark(-5, 10) == 1.0
      assert Grading.mark(20, 10) == 6.0
    end

    test "always on the 0.25 grid within [1, 6]" do
      for points <- 0..40 do
        m = Grading.mark(points / 4, 10)
        assert m >= 1.0 and m <= 6.0
        assert Float.round(m * 4) == m * 4
      end
    end
  end

  describe "formatting" do
    test "format_mark" do
      assert Grading.format_mark(4.0) == "4.0"
      assert Grading.format_mark(4.25) == "4.25"
      assert Grading.format_mark(nil) == "—"
      assert Grading.format_mark(nil, "") == ""
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
