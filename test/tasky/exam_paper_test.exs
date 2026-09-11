defmodule Tasky.ExamPaperTest do
  use ExUnit.Case, async: true

  alias Tasky.ExamPaper

  defp doc(nodes), do: %{"type" => "doc", "content" => nodes}

  defp heading(text, part_id) do
    %{
      "type" => "heading",
      "attrs" => %{"level" => 3, "partId" => part_id},
      "content" => [%{"type" => "text", "text" => text}]
    }
  end

  defp answer_block(id, content \\ [%{"type" => "paragraph"}]) do
    %{"type" => "answerBlock", "attrs" => %{"answerId" => id}, "content" => content}
  end

  defp paragraph(text) do
    %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}
  end

  defp task_item(id, checked, label) do
    %{
      "type" => "taskItem",
      "attrs" => %{"answerId" => id, "checked" => checked},
      "content" => [paragraph(label)]
    }
  end

  defp opts(overrides \\ []) do
    Keyword.merge([answer_mode: "answer_fields"], overrides)
  end

  describe "lines_for_points/1" do
    test "two lines per point" do
      assert ExamPaper.lines_for_points(1) == 2
      assert ExamPaper.lines_for_points(3) == 6
    end

    test "floors at two lines" do
      assert ExamPaper.lines_for_points(0.25) == 2
      assert ExamPaper.lines_for_points(0) == 2
    end

    test "caps at fourteen lines" do
      assert ExamPaper.lines_for_points(8) == 14
      assert ExamPaper.lines_for_points(100) == 14
    end

    test "a question without points gets the generous default" do
      assert ExamPaper.lines_for_points(nil) == 4
      assert ExamPaper.lines_for_points("x") == 4
    end
  end

  describe "points_suffix/1" do
    test "singular and plural" do
      assert ExamPaper.points_suffix(1) == " (1 Punkt)"
      assert ExamPaper.points_suffix(1.0) == " (1 Punkt)"
      assert ExamPaper.points_suffix(4) == " (4 Punkte)"
    end

    test "fractional points go through Grading.format_points/1" do
      assert ExamPaper.points_suffix(2.5) == " (2.5 Punkte)"
    end

    test "no points means no suffix at all, not zero" do
      assert ExamPaper.points_suffix(nil) == nil
      assert ExamPaper.points_suffix("x") == nil
    end
  end

  describe "answer_block_points/2" do
    test "a custom distribution is taken verbatim" do
      content = doc([heading("F1", "q-1"), answer_block("a"), answer_block("b")])

      points =
        ExamPaper.answer_block_points(
          content,
          opts(
            sample_solution_points: %{"q-1" => 5},
            sample_solution_block_points: %{"q-1" => %{"a" => 4, "b" => 1}}
          )
        )

      assert points == %{"a" => 4, "b" => 1}
    end

    test "without a custom distribution the question's points split over answer blocks" do
      content = doc([heading("F1", "q-1"), answer_block("a"), answer_block("b")])

      points =
        ExamPaper.answer_block_points(content, opts(sample_solution_points: %{"q-1" => 6}))

      assert points == %{"a" => 3.0, "b" => 3.0}
    end

    test "checkboxes do not dilute the split" do
      # The whole reason this does not reuse Exams.resolve_block_points/3:
      # splitting over every answer node would leave the field with 1 point.
      content =
        doc([
          heading("F1", "q-1"),
          answer_block("a"),
          task_item("c1", false, "A"),
          task_item("c2", false, "B"),
          task_item("c3", false, "C")
        ])

      points =
        ExamPaper.answer_block_points(content, opts(sample_solution_points: %{"q-1" => 4}))

      assert points == %{"a" => 4.0}
    end

    test "a question without points yields no entry" do
      content = doc([heading("F1", "q-1"), answer_block("a")])

      assert ExamPaper.answer_block_points(content, opts()) == %{}
    end

    test "finds answer blocks nested in tables" do
      cell = %{"type" => "tableCell", "content" => [answer_block("a")]}
      row = %{"type" => "tableRow", "content" => [cell]}
      table = %{"type" => "table", "content" => [row]}
      content = doc([heading("F1", "q-1"), table])

      points =
        ExamPaper.answer_block_points(content, opts(sample_solution_points: %{"q-1" => 2}))

      assert points == %{"a" => 2.0}
    end
  end

  describe "paper_doc/2 — answer boxes" do
    test "the layout decides the number of lines" do
      content = doc([heading("F1", "q-1"), answer_block("a")])

      %{"content" => [_h, block]} =
        ExamPaper.paper_doc(content, opts(layout: %{"a" => 7}))

      assert length(block["content"]) == 7
      assert Enum.all?(block["content"], &(&1 == %{"type" => "paragraph"}))
    end

    test "without a layout entry the box falls back to the point-derived size" do
      content = doc([heading("F1", "q-1"), answer_block("a")])

      %{"content" => [_h, block]} =
        ExamPaper.paper_doc(content, opts(sample_solution_points: %{"q-1" => 3}))

      assert length(block["content"]) == 6
    end

    test "without layout or points the box falls back to the default" do
      content = doc([heading("F1", "q-1"), answer_block("a")])

      %{"content" => [_h, block]} = ExamPaper.paper_doc(content, opts())

      assert length(block["content"]) == 4
    end

    test "a stale layout entry for a deleted field is ignored" do
      content = doc([heading("F1", "q-1"), answer_block("a")])

      %{"content" => [_h, block]} =
        ExamPaper.paper_doc(content, opts(layout: %{"a" => 3, "gone" => 9}))

      assert length(block["content"]) == 3
    end

    test "whatever the teacher typed into a box is replaced by blank lines" do
      content = doc([heading("F1", "q-1"), answer_block("a", [paragraph("Notiz")])])

      %{"content" => [_h, block]} =
        ExamPaper.paper_doc(content, opts(layout: %{"a" => 2}))

      assert block["content"] == [%{"type" => "paragraph"}, %{"type" => "paragraph"}]
    end
  end

  describe "paper_doc/2 — other nodes" do
    test "a checkbox is cleared but keeps its label" do
      content = doc([heading("F1", "q-1"), task_item("c1", true, "Antwort A")])

      %{"content" => [_h, item]} = ExamPaper.paper_doc(content, opts())

      assert item["attrs"]["checked"] == false
      assert item["content"] == [paragraph("Antwort A")]
    end

    test "an inline gap is left untouched — its width is CSS" do
      gap = %{
        "type" => "lueckentext",
        "attrs" => %{"answerId" => "g1"},
        "content" => [%{"type" => "text", "text" => "x"}]
      }

      content = doc([heading("F1", "q-1"), %{"type" => "paragraph", "content" => [gap]}])

      %{"content" => [_h, %{"content" => [out]}]} = ExamPaper.paper_doc(content, opts())

      assert out == gap
    end

    test "a solution hint is dropped" do
      hint = %{"type" => "solutionHint", "content" => [paragraph("Musterlösung")]}
      content = doc([heading("F1", "q-1"), hint, paragraph("bleibt")])

      %{"content" => nodes} = ExamPaper.paper_doc(content, opts())

      refute Enum.any?(nodes, &(&1["type"] == "solutionHint"))
      assert Enum.any?(nodes, &(&1 == paragraph("bleibt")))
    end
  end

  describe "paper_doc/2 — question headings" do
    test "the points are appended to the heading text" do
      content = doc([heading("Frage eins", "q-1"), answer_block("a")])

      %{"content" => [h | _]} =
        ExamPaper.paper_doc(content, opts(sample_solution_points: %{"q-1" => 4}))

      assert h["content"] == [
               %{"type" => "text", "text" => "Frage eins"},
               %{"type" => "text", "text" => " (4 Punkte)"}
             ]
    end

    test "a question without points gets no suffix" do
      content = doc([heading("Frage eins", "q-1"), answer_block("a")])

      %{"content" => [h | _]} = ExamPaper.paper_doc(content, opts())

      assert h["content"] == [%{"type" => "text", "text" => "Frage eins"}]
    end

    test "headings without a partId fall back to positional ids" do
      # A legacy doc: its points are keyed "q-1"/"q-2" positionally. This is
      # why paper_doc/2 must not call ensure_part_ids/1 — random ids would
      # stop matching those keys and the points would silently disappear.
      bare = fn text ->
        %{
          "type" => "heading",
          "attrs" => %{"level" => 3},
          "content" => [%{"type" => "text", "text" => text}]
        }
      end

      content = doc([bare.("Eins"), answer_block("a"), bare.("Zwei"), answer_block("b")])

      %{"content" => [h1, b1, h2, b2]} =
        ExamPaper.paper_doc(content, opts(sample_solution_points: %{"q-1" => 2, "q-2" => 3}))

      assert List.last(h1["content"]) == %{"type" => "text", "text" => " (2 Punkte)"}
      assert List.last(h2["content"]) == %{"type" => "text", "text" => " (3 Punkte)"}
      assert length(b1["content"]) == 4
      assert length(b2["content"]) == 6
    end

    test "the preamble survives" do
      intro = paragraph("Zeit: 90 Minuten")
      content = doc([intro, heading("F1", "q-1"), answer_block("a")])

      %{"content" => [first | _]} = ExamPaper.paper_doc(content, opts())

      assert first == intro
    end
  end

  describe "paper_doc/2 — free_document" do
    test "the document passes through, only checkboxes are cleared" do
      content = doc([paragraph("Aufsatz"), task_item("c1", true, "A")])

      out = ExamPaper.paper_doc(content, answer_mode: "free_document")

      assert [first, item] = out["content"]
      assert first == paragraph("Aufsatz")
      assert item["attrs"]["checked"] == false
    end

    test "no points suffix is added — there are no question headings" do
      h = %{
        "type" => "heading",
        "attrs" => %{"level" => 3},
        "content" => [%{"type" => "text", "text" => "Titel"}]
      }

      out =
        ExamPaper.paper_doc(doc([h]),
          answer_mode: "free_document",
          sample_solution_points: %{"document" => 10}
        )

      assert out["content"] == [h]
    end
  end

  describe "paper_doc/2 — degenerate input" do
    test "nil and empty content do not raise" do
      assert ExamPaper.paper_doc(nil, opts()) == %{"type" => "doc", "content" => []}
      assert ExamPaper.paper_doc(%{}, opts()) == %{"type" => "doc", "content" => []}
      assert ExamPaper.paper_doc(doc([]), opts()) == %{"type" => "doc", "content" => []}
    end
  end

  describe "extract_layout/1" do
    test "counts the paragraphs of each answer block" do
      d =
        doc([
          answer_block("a", List.duplicate(%{"type" => "paragraph"}, 3)),
          answer_block("b", List.duplicate(%{"type" => "paragraph"}, 7))
        ])

      assert ExamPaper.extract_layout(d) == %{"a" => 3, "b" => 7}
    end

    test "text the teacher typed is not persisted — only the line count is" do
      d = doc([answer_block("a", [paragraph("Notiz"), %{"type" => "paragraph"}])])

      assert ExamPaper.extract_layout(d) == %{"a" => 2}
    end

    test "non-paragraph children are not counted as lines" do
      d =
        doc([
          answer_block("a", [
            %{"type" => "paragraph"},
            %{"type" => "bulletList", "content" => []}
          ])
        ])

      assert ExamPaper.extract_layout(d) == %{"a" => 1}
    end

    test "inline gaps contribute nothing" do
      gap = %{
        "type" => "lueckentext",
        "attrs" => %{"answerId" => "g1"},
        "content" => [%{"type" => "text", "text" => "getippt"}]
      }

      d = doc([%{"type" => "paragraph", "content" => [gap]}])

      assert ExamPaper.extract_layout(d) == %{}
    end

    test "an answer block without an answerId yields no entry" do
      d = doc([%{"type" => "answerBlock", "content" => [%{"type" => "paragraph"}]}])

      assert ExamPaper.extract_layout(d) == %{}
    end

    test "finds answer blocks nested in tables" do
      cell = %{
        "type" => "tableCell",
        "content" => [answer_block("a", List.duplicate(%{"type" => "paragraph"}, 2))]
      }

      d = doc([%{"type" => "table", "content" => [%{"type" => "tableRow", "content" => [cell]}]}])

      assert ExamPaper.extract_layout(d) == %{"a" => 2}
    end

    test "nil and empty input" do
      assert ExamPaper.extract_layout(nil) == %{}
      assert ExamPaper.extract_layout(%{}) == %{}
    end
  end

  describe "round trip" do
    test "paper_doc |> extract_layout returns the layout it was given" do
      # The property the save path lives on: the paper editor sends a whole
      # document, and only the line counts come back out.
      content =
        doc([
          heading("F1", "q-1"),
          answer_block("a"),
          heading("F2", "q-2"),
          %{
            "type" => "table",
            "content" => [
              %{
                "type" => "tableRow",
                "content" => [%{"type" => "tableCell", "content" => [answer_block("b")]}]
              }
            ]
          }
        ])

      layout = %{"a" => 5, "b" => 11}

      assert content
             |> ExamPaper.paper_doc(opts(layout: layout))
             |> ExamPaper.extract_layout() == layout
    end

    test "the point-derived defaults round trip too" do
      content = doc([heading("F1", "q-1"), answer_block("a")])
      o = opts(sample_solution_points: %{"q-1" => 3})

      assert content |> ExamPaper.paper_doc(o) |> ExamPaper.extract_layout() == %{"a" => 6}
    end
  end
end
