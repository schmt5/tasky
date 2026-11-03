defmodule Tasky.Correction.PlainAnswersTest do
  use ExUnit.Case, async: true

  alias Tasky.Correction.PlainAnswers

  defp p(text), do: %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}

  @skeleton %{
    "type" => "doc",
    "content" => [
      %{
        "type" => "answerBlock",
        "attrs" => %{"answerId" => 1},
        "content" => [%{"type" => "paragraph"}]
      },
      %{
        "type" => "paragraph",
        "content" => [
          %{"type" => "text", "text" => "Die Hauptstadt ist "},
          %{"type" => "lueckentext", "attrs" => %{"answerId" => "gap"}},
          %{"type" => "choice", "attrs" => %{"groupId" => 7, "optionId" => "o_a"}},
          %{"type" => "choice", "attrs" => %{"groupId" => 7, "optionId" => "o_b"}}
        ]
      },
      %{
        "type" => "taskList",
        "content" => [
          %{
            "type" => "taskItem",
            "attrs" => %{"answerId" => "mc", "checked" => false},
            "content" => [
              %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Bern"}]}
            ]
          }
        ]
      }
    ]
  }

  describe "from_params/2" do
    test "turns each field value into its AnswerKey payload" do
      params = %{
        "answers" => %{"1" => "Zeile eins\nZeile zwei", "gap" => "Bern", "mc" => true},
        "choices" => %{"7" => "o_b"}
      }

      assert {:ok, answers} = PlainAnswers.from_params(@skeleton, params)

      assert answers == %{
               "1" => [p("Zeile eins"), p("Zeile zwei")],
               "gap" => [%{"type" => "text", "text" => "Bern"}],
               "mc" => true,
               "7" => "o_b"
             }
    end

    test "drops unknown ids, wrong value types and foreign options" do
      params = %{
        "answers" => %{"nope" => "x", "mc" => "true", "gap" => 3},
        "choices" => %{"7" => "o_fremd", "99" => "o_a"}
      }

      assert {:ok, %{}} = PlainAnswers.from_params(@skeleton, params)
    end

    test "an empty choice means nothing chosen" do
      assert {:ok, %{"7" => nil}} =
               PlainAnswers.from_params(@skeleton, %{"choices" => %{"7" => nil}})
    end

    test "refuses values over the limit" do
      gap = String.duplicate("x", PlainAnswers.max_gap_chars() + 1)

      assert {:error, :too_long} =
               PlainAnswers.from_params(@skeleton, %{"answers" => %{"gap" => gap}})
    end

    test "survives garbage params" do
      assert {:ok, %{}} =
               PlainAnswers.from_params(@skeleton, %{"answers" => "x", "choices" => [1]})
    end
  end

  describe "block_nodes/1 and gap_nodes/1" do
    test "keeps empty lines as empty paragraphs" do
      assert PlainAnswers.block_nodes("a\r\n\nb") == [p("a"), %{"type" => "paragraph"}, p("b")]
      assert PlainAnswers.block_nodes("") == [%{"type" => "paragraph"}]
    end

    test "flattens a gap to one line" do
      assert PlainAnswers.gap_nodes("a\nb") == [%{"type" => "text", "text" => "a b"}]
      assert PlainAnswers.gap_nodes("") == []
    end
  end

  describe "block_text/1" do
    test "round-trips its own output" do
      text = "erste\n\ndritte"
      assert text |> PlainAnswers.block_nodes() |> PlainAnswers.block_text() == text
    end

    test "flattens rich answers from the Tiptap editor" do
      nodes = [
        %{
          "type" => "paragraph",
          "content" => [
            %{"type" => "text", "text" => "fett", "marks" => [%{"type" => "bold"}]},
            %{"type" => "hardBreak"},
            %{"type" => "text", "text" => "weiter"}
          ]
        },
        %{
          "type" => "bulletList",
          "content" => [
            %{"type" => "listItem", "content" => [p("eins")]},
            %{
              "type" => "listItem",
              "content" => [
                p("zwei"),
                %{
                  "type" => "orderedList",
                  "content" => [%{"type" => "listItem", "content" => [p("a")]}]
                }
              ]
            }
          ]
        },
        %{
          "type" => "table",
          "content" => [
            %{
              "type" => "tableRow",
              "content" => [
                %{"type" => "tableCell", "content" => [p("x")]},
                %{"type" => "tableCell", "content" => [p("y")]}
              ]
            }
          ]
        }
      ]

      assert PlainAnswers.block_text(nodes) ==
               "fett\nweiter\n• eins\n• zwei\n  1. a\nx | y"
    end
  end

  test "gap_text/1 reads inline content" do
    assert PlainAnswers.gap_text([
             %{"type" => "text", "text" => "Bern", "marks" => [%{"type" => "italic"}]}
           ]) ==
             "Bern"

    assert PlainAnswers.gap_text(nil) == ""
  end
end
