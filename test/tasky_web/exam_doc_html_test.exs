defmodule TaskyWeb.ExamDocHTMLTest do
  use ExUnit.Case, async: true

  alias TaskyWeb.ExamDocHTML

  defp render_doc(nodes, opts \\ []) do
    %{"type" => "doc", "content" => nodes}
    |> ExamDocHTML.render(Keyword.put_new(opts, :id, "s"))
    |> Phoenix.HTML.safe_to_string()
    |> LazyHTML.from_fragment()
  end

  defp text(t, marks \\ []), do: %{"type" => "text", "text" => t, "marks" => marks}
  defp p(content), do: %{"type" => "paragraph", "content" => content}

  defp attr(doc, selector, name) do
    doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
  end

  describe "answer fields" do
    test "a gap becomes a text input carrying its answer" do
      doc =
        render_doc([
          %{"type" => "heading", "attrs" => %{"level" => 3}, "content" => [text("Hauptstadt")]},
          p([
            text("Die Hauptstadt ist "),
            %{"type" => "lueckentext", "attrs" => %{"answerId" => 5}, "content" => [text("Bern")]}
          ])
        ])

      assert attr(doc, "input.exam-doc__gap", "data-answer-id") == ["5"]
      assert attr(doc, "input.exam-doc__gap", "value") == ["Bern"]
      assert attr(doc, "input.exam-doc__gap", "aria-label") == ["Lücke 1 zu: Hauptstadt"]
      assert attr(doc, "input.exam-doc__gap", "spellcheck") == ["false"]
    end

    test "an answer block becomes a textarea with its plain text" do
      doc =
        render_doc([
          %{
            "type" => "answerBlock",
            "attrs" => %{"answerId" => "a"},
            "content" => [p([text("eins", [%{"type" => "bold"}])]), p([text("zwei")])]
          }
        ])

      assert attr(doc, "textarea", "data-answer-id") == ["a"]
      assert doc |> LazyHTML.query("textarea") |> LazyHTML.text() == "eins\nzwei"
    end

    test "multiple choice is a checkbox, single choice a radio group" do
      doc =
        render_doc([
          %{
            "type" => "taskList",
            "content" => [
              %{
                "type" => "taskItem",
                "attrs" => %{"answerId" => "mc", "checked" => true},
                "content" => [p([text("Bern")])]
              }
            ]
          },
          p([
            %{"type" => "choice", "attrs" => %{"groupId" => 9, "optionId" => "o_a"}},
            text("Ja "),
            %{
              "type" => "choice",
              "attrs" => %{"groupId" => 9, "optionId" => "o_b", "checked" => true}
            },
            text("Nein")
          ])
        ])

      assert attr(doc, "input[type=checkbox]", "data-answer-id") == ["mc"]
      assert attr(doc, "input[type=checkbox]", "checked") == [""]

      assert attr(doc, "input[type=radio]", "name") == ["s-choice-9", "s-choice-9"]
      assert attr(doc, "input[type=radio]", "aria-label") == ["Ja", "Nein"]
      assert attr(doc, "input[type=radio][checked]", "value") == ["o_b"]
    end

    test "the option text is the checkbox's label; further paragraphs sit below" do
      doc =
        render_doc([
          %{
            "type" => "taskList",
            "content" => [
              %{
                "type" => "taskItem",
                "attrs" => %{"answerId" => "mc"},
                "content" => [p([text("Bern", [%{"type" => "bold"}])]), p([text("Hinweis")])]
              }
            ]
          }
        ])

      label = LazyHTML.query(doc, "label.exam-doc__option")
      assert label |> LazyHTML.query("input[type=checkbox]") |> Enum.count() == 1
      assert label |> LazyHTML.query("span strong") |> LazyHTML.text() == "Bern"
      # A <label> takes phrasing content only.
      assert label |> LazyHTML.query("p") |> Enum.count() == 0
      assert doc |> LazyHTML.query(".exam-doc__option-more p") |> LazyHTML.text() == "Hinweis"
    end

    test "a field inside a multiple-choice label stays text — AnswerKey never saves it" do
      doc =
        render_doc([
          %{
            "type" => "taskList",
            "content" => [
              %{
                "type" => "taskItem",
                "attrs" => %{"answerId" => "mc"},
                "content" => [
                  p([
                    %{
                      "type" => "lueckentext",
                      "attrs" => %{"answerId" => "x"},
                      "content" => [text("Bern")]
                    }
                  ])
                ]
              }
            ]
          }
        ])

      assert doc |> LazyHTML.query("input.exam-doc__gap") |> Enum.count() == 0
      assert doc |> LazyHTML.text() =~ "Bern"
    end

    test "an essay field becomes an editor container carrying its answer as JSON" do
      answer = [
        %{"type" => "heading", "attrs" => %{"level" => 4}, "content" => [text("Einleitung")]},
        p([text("eins", [%{"type" => "bold"}])])
      ]

      doc =
        render_doc([
          %{
            "type" => "answerBlock",
            "attrs" => %{"answerId" => "e", "rich" => true},
            "content" => answer
          }
        ])

      assert doc |> LazyHTML.query("textarea") |> Enum.count() == 0
      assert attr(doc, ".exam-doc__rich", "data-answer-id") == ["e"]
      assert [json] = attr(doc, ".exam-doc__rich", "data-value")
      assert Jason.decode!(json) == answer
      # Shown as formatted text until the editor runs.
      assert doc |> LazyHTML.query(".exam-doc__rich h4") |> LazyHTML.text() == "Einleitung"
      assert doc |> LazyHTML.query(".exam-doc__rich strong") |> LazyHTML.text() == "eins"
    end

    test "a disabled essay field is marked for the editor to stay read-only" do
      doc =
        render_doc(
          [%{"type" => "answerBlock", "attrs" => %{"answerId" => 1, "rich" => true}}],
          disabled: true
        )

      assert attr(doc, ".exam-doc__rich", "data-disabled") == [""]
    end

    test "a pin image carries its pins' ids and positions, never a zone" do
      pins = [
        %{"pinId" => "a", "x" => 0.25, "y" => 0.5, "zone" => %{"shape" => "circle", "r" => 0.1}},
        %{"pinId" => "b"}
      ]

      doc =
        render_doc([
          %{
            "type" => "imagePin",
            "attrs" => %{
              "answerId" => "img",
              "src" => "/uploads/a.png",
              "aspect" => 2,
              "pins" => pins
            }
          }
        ])

      assert [json] = attr(doc, ".exam-doc__pin", "data-value")

      assert Jason.decode!(json) == [
               %{"pinId" => "a", "x" => 0.25, "y" => 0.5},
               %{"pinId" => "b"}
             ]

      assert attr(doc, ".exam-doc__pin img", "src") == ["/uploads/a.png"]
      assert doc |> LazyHTML.query(".exam-doc__pin-marker") |> LazyHTML.text() == "1"
    end

    test "a pin image from another site is left out" do
      doc =
        render_doc([
          %{
            "type" => "imagePin",
            "attrs" => %{"answerId" => "img", "src" => "//evil.example/a.png"}
          }
        ])

      assert doc |> LazyHTML.query(".exam-doc__pin") |> Enum.count() == 0
    end

    test "disabled locks every field" do
      doc =
        render_doc(
          [
            p([%{"type" => "lueckentext", "attrs" => %{"answerId" => 1}}]),
            %{"type" => "answerBlock", "attrs" => %{"answerId" => 2}, "content" => [p([])]}
          ],
          disabled: true
        )

      assert attr(doc, "[data-answer-id]", "disabled") == ["", ""]
    end
  end

  describe "content" do
    test "escapes text and attributes" do
      doc =
        render_doc([
          p([text("<script>alert(1)</script>")]),
          %{
            "type" => "answerBlock",
            "attrs" => %{"answerId" => "a"},
            "content" => [p([text("</textarea><b>x</b>")])]
          }
        ])

      assert doc |> LazyHTML.query("script, b") |> Enum.count() == 0
      assert doc |> LazyHTML.query("p") |> LazyHTML.text() == "<script>alert(1)</script>"
    end

    test "keeps only safe links and colours" do
      doc =
        render_doc([
          p([
            text("gut", [%{"type" => "link", "attrs" => %{"href" => "https://example.org"}}]),
            text("böse", [%{"type" => "link", "attrs" => %{"href" => "javascript:alert(1)"}}]),
            text("rot", [%{"type" => "textStyle", "attrs" => %{"color" => "#ea580c"}}]),
            text("css", [
              %{"type" => "textStyle", "attrs" => %{"color" => "red;background:url(x)"}}
            ])
          ])
        ])

      assert attr(doc, "a", "href") == ["https://example.org"]
      assert attr(doc, "span", "style") == ["color: #ea580c"]
    end

    # One entry per node type of the editor schema
    # (assets/js/react/editor/editorExtensions.ts). A type added there needs a
    # branch here — this list is the reminder.
    test "renders every node type of the editor schema" do
      cases = [
        {%{"type" => "heading", "attrs" => %{"level" => 2}, "content" => [text("T")]}, "h2"},
        {p([text("a"), %{"type" => "hardBreak"}, text("b")]), "p br"},
        {%{
           "type" => "bulletList",
           "content" => [%{"type" => "listItem", "content" => [p([text("x")])]}]
         }, "ul li"},
        {%{
           "type" => "orderedList",
           "attrs" => %{"start" => 3},
           "content" => [%{"type" => "listItem", "content" => [p([text("x")])]}]
         }, "ol[start='3'] li"},
        {%{"type" => "blockquote", "content" => [p([text("q")])]}, "blockquote p"},
        {%{"type" => "callout", "attrs" => %{"color" => "blue"}, "content" => [p([text("c")])]},
         "div.callout[data-color=blue]"},
        {%{"type" => "codeBlock", "content" => [text("x = 1")]}, "pre code"},
        {%{
           "type" => "table",
           "content" => [
             %{
               "type" => "tableRow",
               "content" => [
                 %{"type" => "tableHeader", "content" => [p([text("h")])]},
                 %{
                   "type" => "tableCell",
                   "attrs" => %{"colspan" => 2},
                   "content" => [p([text("c")])]
                 }
               ]
             }
           ]
         }, "table tr th + td[colspan='2']"},
        {%{"type" => "image", "attrs" => %{"src" => "/uploads/exams/1/x.png", "alt" => "Bild"}},
         "img[alt=Bild]"},
        {%{"type" => "taskList", "content" => []}, "ul[data-type=taskList]"}
      ]

      for {node, selector} <- cases do
        assert render_doc([node]) |> LazyHTML.query(selector) |> Enum.count() > 0,
               "#{node["type"]} did not render #{selector}"
      end
    end

    test "drops images from foreign or unsafe sources" do
      for src <- ["javascript:x", "//evil.example/a.png"] do
        doc = render_doc([%{"type" => "image", "attrs" => %{"src" => src}}])
        assert doc |> LazyHTML.query("img") |> Enum.count() == 0
      end
    end

    test "walks through an unknown node instead of failing" do
      doc = render_doc([%{"type" => "mystery", "content" => [p([text("drin")])]}])
      assert doc |> LazyHTML.text() == "drin"
    end
  end

  describe "audio" do
    @audio %{
      "type" => "audio",
      "attrs" => %{
        "audioId" => "hoer-1",
        "src" => "/uploads/exams/7/a.mp3",
        "title" => "Hörtext",
        "maxPlays" => 2
      }
    }

    test "a placeholder with the plays and the limit, but no file" do
      doc =
        render_doc([@audio],
          audio_plays: %{"hoer-1" => %{"started" => 1, "active" => true, "position" => 3.5}}
        )

      assert attr(doc, "[data-audio]", "data-audio-id") == ["hoer-1"]
      assert attr(doc, "[data-audio]", "data-max-plays") == ["2"]
      assert attr(doc, "[data-audio]", "data-src") == []

      assert [state] = attr(doc, "[data-audio]", "data-state")
      assert %{"started" => 1, "active" => true} = Jason.decode!(state)
    end

    test "the teacher's preview carries their own route" do
      doc = render_doc([@audio], teacher_audio: true)
      assert attr(doc, "[data-audio]", "data-src") == ["/exams/7/audio/a.mp3"]
    end

    test "a block without an id renders nothing" do
      doc = render_doc([%{"type" => "audio", "attrs" => %{"src" => "/uploads/exams/7/a.mp3"}}])
      assert attr(doc, "[data-audio]", "data-audio-id") == []
    end
  end

  describe "points per question" do
    defp question(attrs) do
      %{
        "type" => "heading",
        "attrs" => Map.merge(%{"level" => 3}, attrs),
        "content" => [text("Hauptstadt")]
      }
    end

    defp gap, do: p([%{"type" => "lueckentext", "attrs" => %{"answerId" => 5}}])

    test "a marked question shows what it is worth under its heading" do
      doc = render_doc([question(%{"maxPoints" => 4}), gap()])

      assert doc |> LazyHTML.query("h3 + p.exam-doc__points") |> LazyHTML.text() == "4 Punkte"
    end

    test "one point is singular, quarters stay" do
      one = render_doc([question(%{"maxPoints" => 1})])
      quarter = render_doc([question(%{"maxPoints" => 2.25})])

      assert one |> LazyHTML.query(".exam-doc__points") |> LazyHTML.text() == "1 Punkt"
      assert quarter |> LazyHTML.query(".exam-doc__points") |> LazyHTML.text() == "2.25 Punkte"
    end

    test "an unmarked question shows nothing" do
      doc = render_doc([question(%{}), gap()])

      assert doc |> LazyHTML.query(".exam-doc__points") |> Enum.count() == 0
    end

    test "the points stay out of the fields' label" do
      doc = render_doc([question(%{"maxPoints" => 4}), gap()])

      assert attr(doc, "input.exam-doc__gap", "aria-label") == ["Lücke 1 zu: Hauptstadt"]
    end
  end
end
