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

    test "ignore_punctuation drops punctuation on both sides" do
      opts = %{ignore_punctuation: true}

      refute StringComparator.text_match?("Hallo Welt", "Hallo, Welt!", %{})
      assert StringComparator.text_match?("Hallo Welt", "Hallo, Welt!", opts)
      assert StringComparator.text_match?("Hallo , Welt?", "Hallo Welt", opts)
      assert StringComparator.text_match?("«Ja.»", "Ja", opts)
      refute StringComparator.text_match?("Hallo Welt", "Hallo Welten", opts)
    end

    test "ignore_punctuation combines with ignore_case" do
      assert StringComparator.text_match?("hallo welt", "Hallo, Welt.", %{
               ignore_punctuation: true,
               ignore_case: true
             })
    end
  end

  describe "match_opts/1" do
    test "reads the text flags from a part config" do
      assert StringComparator.match_opts(%{"ignore_case" => true, "ignore_punctuation" => true}) ==
               %{ignore_case: true, ignore_spelling: false, ignore_punctuation: true}

      assert StringComparator.match_opts(nil) ==
               %{ignore_case: false, ignore_spelling: false, ignore_punctuation: false}
    end
  end

  describe "correct_part/4 with ignore_punctuation" do
    test "accepts an answer that differs only in punctuation, per alternative" do
      sample = [
        %{
          "type" => "answerBlock",
          "content" => [
            %{
              "type" => "paragraph",
              "content" => [%{"type" => "text", "text" => "Ja, gern!; Nein."}]
            }
          ]
        }
      ]

      student = fn text ->
        [
          %{
            "type" => "answerBlock",
            "attrs" => %{"__ai_id" => 1},
            "content" => [
              %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}
            ]
          }
        ]
      end

      opts = %{ignore_punctuation: true}

      assert {:ok, %{verdicts: %{1 => "correct"}}} =
               StringComparator.correct_part(student.("Ja gern"), sample, 1, opts)

      assert {:ok, %{verdicts: %{1 => "correct"}}} =
               StringComparator.correct_part(student.("Nein"), sample, 1, opts)

      assert {:ok, %{verdicts: %{1 => "wrong"}}} =
               StringComparator.correct_part(student.("Ja gern"), sample, 1, %{})
    end
  end
end
