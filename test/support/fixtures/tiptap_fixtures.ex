defmodule Tasky.TiptapFixtures do
  @moduledoc """
  A Tiptap document using every node and mark the exam editor knows, for
  renderer tests (`Tasky.PDF`).
  """

  def text(text, marks \\ []), do: %{"type" => "text", "text" => text, "marks" => marks}

  def paragraph(inlines), do: %{"type" => "paragraph", "content" => inlines}

  def kitchen_sink_doc do
    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "heading",
          "attrs" => %{"level" => 1},
          "content" => [text("Titel mit # $ * ] <% eex %> \\ ` _ @ ~")]
        },
        %{"type" => "heading", "attrs" => %{"level" => 2}, "content" => [text("Abschnitt")]},
        %{
          "type" => "heading",
          "attrs" => %{"level" => 3, "partId" => "p1"},
          "content" => [text("Frage 1 (4 Punkte)")]
        },
        paragraph([
          text("fett ", [%{"type" => "bold"}]),
          text("kursiv ", [%{"type" => "italic"}]),
          text("unterstrichen ", [%{"type" => "underline"}]),
          text("durchgestrichen ", [%{"type" => "strike"}]),
          text("code ", [%{"type" => "code"}]),
          text("link ", [%{"type" => "link", "attrs" => %{"href" => "https://example.com"}}]),
          text("farbig ", [%{"type" => "textStyle", "attrs" => %{"color" => "#2563eb"}}]),
          text("ungültige Farbe ", [
            %{"type" => "textStyle", "attrs" => %{"color" => "rgb(1, 2, 3)"}}
          ]),
          text("markiert ", [%{"type" => "highlight", "attrs" => %{"color" => "#fef08a"}}]),
          text("kommentar", [%{"type" => "teacherComment"}]),
          %{"type" => "hardBreak"},
          text("Lücke: "),
          %{
            "type" => "lueckentext",
            "attrs" => %{"answerId" => "a1", "verdict" => "correct"},
            "content" => [text("Bern")]
          },
          text(" und "),
          %{"type" => "lueckentext", "attrs" => %{"answerId" => "a2"}},
          text(" und "),
          %{
            "type" => "lueckentext",
            "attrs" => %{"answerId" => "a3", "verdict" => "wrong"},
            "content" => [text("Zürich")]
          }
        ]),
        paragraph([]),
        %{
          "type" => "answerBlock",
          "attrs" => %{"answerId" => "a4", "verdict" => "half"},
          "content" => [paragraph([text("Eine halbe Antwort.")])]
        },
        %{
          "type" => "solutionHint",
          "content" => [paragraph([text("Die vollständige Antwort.")])]
        },
        %{
          "type" => "answerBlock",
          "attrs" => %{"answerId" => "a5"},
          "content" => [paragraph([])]
        },
        %{
          "type" => "taskList",
          "content" => [
            %{
              "type" => "taskItem",
              "attrs" => %{"checked" => true, "answerId" => "a6", "verdict" => "correct"},
              "content" => [paragraph([text("Richtig angekreuzt")])]
            },
            %{
              "type" => "taskItem",
              "attrs" => %{"checked" => false, "answerId" => "a7"},
              "content" => [paragraph([text("Nicht bewertet")])]
            }
          ]
        },
        # Single choice: the chosen radio was wrong, the right one is marked.
        paragraph([
          %{
            "type" => "choice",
            "attrs" => %{
              "groupId" => "c1",
              "optionId" => "o1",
              "checked" => true,
              "verdict" => "wrong"
            }
          },
          text(" analog "),
          %{
            "type" => "choice",
            "attrs" => %{
              "groupId" => "c1",
              "optionId" => "o2",
              "checked" => false,
              "verdict" => "wrong",
              "correct" => true
            }
          },
          text(" digital")
        ]),
        %{
          "type" => "bulletList",
          "content" => [
            %{
              "type" => "listItem",
              "content" => [
                paragraph([text("Punkt")]),
                %{
                  "type" => "orderedList",
                  "attrs" => %{"start" => 3},
                  "content" => [
                    %{"type" => "listItem", "content" => [paragraph([text("verschachtelt")])]}
                  ]
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
                %{
                  "type" => "tableHeader",
                  "attrs" => %{"colspan" => 2},
                  "content" => [paragraph([text("Kopf")])]
                }
              ]
            },
            %{
              "type" => "tableRow",
              "content" => [
                %{"type" => "tableCell", "content" => [paragraph([text("A")])]},
                %{"type" => "tableCell", "content" => [paragraph([text("B")])]}
              ]
            }
          ]
        },
        %{
          "type" => "callout",
          "attrs" => %{"color" => "blue"},
          "content" => [paragraph([text("Hinweis")])]
        },
        %{"type" => "callout", "attrs" => %{"color" => "bogus"}, "content" => [paragraph([])]},
        %{"type" => "blockquote", "content" => [paragraph([text("Zitat")])]},
        %{"type" => "codeBlock", "content" => [text("IO.puts(\"#hi\")")]},
        %{"type" => "image", "attrs" => %{"src" => "https://example.com/extern.png"}},
        %{"type" => "someFutureNode", "content" => [paragraph([text("unbekannt")])]}
      ]
    }
  end

  @doc "A bullet list nested `depth` levels deep."
  def deeply_nested_doc(depth) do
    leaf = paragraph([text("ganz unten")])

    nested =
      Enum.reduce(1..depth, leaf, fn _, inner ->
        %{
          "type" => "bulletList",
          "content" => [%{"type" => "listItem", "content" => [paragraph([text("Ebene")]), inner]}]
        }
      end)

    %{"type" => "doc", "content" => [nested]}
  end
end
