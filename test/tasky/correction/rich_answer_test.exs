defmodule Tasky.Correction.RichAnswerTest do
  use ExUnit.Case, async: true

  alias Tasky.Correction.RichAnswer

  defp text(t, marks \\ []), do: %{"type" => "text", "text" => t, "marks" => marks}
  defp p(content), do: %{"type" => "paragraph", "content" => content}
  defp clean(t), do: %{"type" => "text", "text" => t}

  test "keeps paragraphs, lists and the allowed marks" do
    nodes = [
      p([text("a", [%{"type" => "bold"}, %{"type" => "italic"}, %{"type" => "underline"}])]),
      %{
        "type" => "orderedList",
        "attrs" => %{"start" => 3, "type" => "a"},
        "content" => [%{"type" => "listItem", "content" => [p([text("b")])]}]
      }
    ]

    assert {:ok,
            [
              %{"type" => "paragraph", "content" => [%{"marks" => marks}]},
              %{
                "type" => "orderedList",
                "attrs" => %{"start" => 3},
                "content" => [%{"type" => "listItem", "content" => [%{"type" => "paragraph"}]}]
              }
            ]} = RichAnswer.sanitize(nodes)

    assert marks == [%{"type" => "bold"}, %{"type" => "italic"}, %{"type" => "underline"}]
  end

  test "every heading becomes level 4 — a learner's h3 would cut the exam into parts" do
    assert {:ok, [%{"type" => "heading", "attrs" => %{"level" => 4}}]} =
             RichAnswer.sanitize([
               %{
                 "type" => "heading",
                 "attrs" => %{"level" => 3, "partId" => "q-x"},
                 "content" => [text("T")]
               }
             ])
  end

  test "unknown nodes give their text, unknown leaves and marks disappear" do
    nodes = [
      %{"type" => "callout", "content" => [p([text("zitiert", [%{"type" => "link"}])])]},
      %{"type" => "image", "attrs" => %{"src" => "/x.png"}},
      %{"type" => "answerBlock", "attrs" => %{"answerId" => 9}, "content" => [p([text("innen")])]}
    ]

    assert RichAnswer.sanitize(nodes) == {:ok, [p([clean("zitiert")]), p([clean("innen")])]}
  end

  test "keeps a blockquote with its blocks, and a highlight without its colour" do
    nodes = [
      %{
        "type" => "blockquote",
        "attrs" => %{"class" => "x"},
        "content" => [
          p([text("zitiert", [%{"type" => "highlight", "attrs" => %{"color" => "red"}}])]),
          %{
            "type" => "bulletList",
            "content" => [%{"type" => "listItem", "content" => [p([text("b")])]}]
          }
        ]
      },
      %{"type" => "blockquote", "content" => []}
    ]

    assert {:ok, [%{"type" => "blockquote", "content" => [quoted, %{"type" => "bulletList"}]}]} =
             RichAnswer.sanitize(nodes)

    assert quoted ==
             p([%{"type" => "text", "text" => "zitiert", "marks" => [%{"type" => "highlight"}]}])
  end

  test "loose inline content is gathered into a paragraph" do
    assert RichAnswer.sanitize([text("a"), %{"type" => "hardBreak"}, text("b")]) ==
             {:ok, [p([clean("a"), %{"type" => "hardBreak"}, clean("b")])]}
  end

  test "a list item always starts with a paragraph" do
    nodes = [
      %{
        "type" => "bulletList",
        "content" => [
          %{
            "type" => "listItem",
            "content" => [
              %{
                "type" => "bulletList",
                "content" => [%{"type" => "listItem", "content" => [p([text("x")])]}]
              }
            ]
          },
          p([text("lose")])
        ]
      }
    ]

    assert {:ok, [%{"type" => "bulletList", "content" => [first, second]}]} =
             RichAnswer.sanitize(nodes)

    assert [%{"type" => "paragraph"}, %{"type" => "bulletList"}] = first["content"]
    assert second == %{"type" => "listItem", "content" => [p([clean("lose")])]}
  end

  test "refuses text over the limit" do
    long = String.duplicate("a", RichAnswer.max_chars() + 1)
    assert RichAnswer.sanitize([p([text(long)])]) == {:error, :too_long}
  end

  test "anything but a node list is an empty answer" do
    assert RichAnswer.sanitize("text") == {:ok, []}
    assert RichAnswer.sanitize(nil) == {:ok, []}
  end
end
