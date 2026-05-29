defmodule Tasky.Correction.StringComparatorTest do
  use ExUnit.Case, async: true

  alias Tasky.Correction.StringComparator

  describe "text_match?/3 (shared by auto-correction and bulk default verdicts)" do
    test "is case-sensitive when ignore_case is off" do
      refute StringComparator.text_match?("la difficulté", "La difficulté", %{})
      assert StringComparator.text_match?("La difficulté", "La difficulté", %{})
    end

    test "is case-insensitive when ignore_case is on" do
      assert StringComparator.text_match?("la difficulté", "La difficulté", %{ignore_case: true})
    end

    test "trims surrounding whitespace before comparing" do
      assert StringComparator.text_match?("  vaste ", "vaste", %{})
    end

    test "ignore_spelling allows fuzzy matches above the threshold" do
      refute StringComparator.text_match?("vaster", "vaste", %{})
      assert StringComparator.text_match?("vaster", "vaste", %{ignore_spelling: true})
    end
  end
end
