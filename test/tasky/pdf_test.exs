defmodule Tasky.PDFTest do
  use ExUnit.Case, async: true

  import Tasky.TiptapFixtures

  alias Tasky.PDF

  @moduletag :capture_log

  defp image(src), do: %{"type" => "image", "attrs" => %{"src" => src}}

  defp doc(nodes), do: %{"type" => "doc", "content" => nodes}

  defp submission_data(sections) do
    %{
      "exam_name" => "Prüfung",
      "student_name" => "Anna Muster",
      "show_points_and_mark" => true,
      "points" => "12,5",
      "max_points" => "20",
      "six_hint" => nil,
      "mark" => "4.5",
      "sections" => sections
    }
  end

  defp paper_data(doc, opts \\ []) do
    %{
      "exam_name" => "Prüfung",
      "max_points" => Keyword.get(opts, :max_points, "20"),
      "doc" => doc,
      "free_document" => Keyword.get(opts, :free_document, false),
      "lined_pages" => Keyword.get(opts, :lined_pages, 0),
      "rules_per_page" => 24
    }
  end

  # A real PNG, so Typst has something it can decode.
  defp png do
    {:ok, [png]} = Typst.render_to_png("#set page(width: 20pt, height: 20pt)\n#rect()", [])
    png
  end

  describe "prepare/2" do
    test "maps each image src to an asset, loading a repeated one once" do
      test_pid = self()

      read = fn src ->
        send(test_pid, {:read, src})
        {:ok, {"bytes-of-" <> src, ".png"}}
      end

      data = doc([image("/uploads/exams/1/a.png"), image("/uploads/exams/1/a.png")])

      {prepared, assets} = PDF.prepare(data, read)

      assert [%{"attrs" => %{"src" => path}}, %{"attrs" => %{"src" => path}}] =
               prepared["content"]

      assert path == "/img/0.png"
      assert assets == [{"img/0.png", "bytes-of-/uploads/exams/1/a.png"}]
      assert_received {:read, "/uploads/exams/1/a.png"}
      refute_received {:read, _}
    end

    test "an image that cannot be loaded gets no src" do
      data = doc([image("https://example.com/x.png"), image(nil)])

      {prepared, assets} = PDF.prepare(data, fn _ -> {:error, :unsupported_src} end)

      assert [%{"attrs" => %{"src" => nil}}, %{"attrs" => %{"src" => nil}}] =
               prepared["content"]

      assert assets == []
    end

    test "flattens content nested too deep for Typst into its text" do
      {prepared, []} = PDF.prepare(deeply_nested_doc(25), fn _ -> {:error, :none} end)

      flattened =
        Stream.iterate(prepared, fn node -> node |> Map.get("content", []) |> List.last() end)
        |> Enum.find(&match?(%{"type" => "paragraph", "content" => [%{"type" => "text"}]}, &1))

      assert flattened, "expected a flattened paragraph"
      [%{"text" => text}] = flattened["content"]
      assert text =~ "ganz unten"
    end

    test "keeps hex colours and drops everything else" do
      mark = fn type, color -> %{"type" => type, "attrs" => %{"color" => color}} end

      data =
        doc([
          paragraph([
            text("a", [mark.("textStyle", "#2563eb")]),
            text("b", [mark.("textStyle", "rgb(1, 2, 3)")]),
            text("c", [mark.("highlight", "#fef08a")]),
            text("d", [mark.("highlight", "red); evil(")])
          ])
        ])

      {prepared, []} = PDF.prepare(data, fn _ -> {:error, :none} end)
      [%{"content" => texts}] = prepared["content"]

      assert Enum.map(texts, fn %{"marks" => [m]} -> m["attrs"]["color"] end) ==
               ["#2563eb", nil, "#fef08a", nil]
    end
  end

  describe "render/2" do
    test "renders every node and mark the editor knows" do
      data =
        submission_data([
          %{"key" => "content", "heading" => nil, "doc" => kitchen_sink_doc()},
          %{"key" => "sample", "heading" => "Musterlösung", "doc" => kitchen_sink_doc()}
        ])

      assert {:ok, "%PDF" <> _} = PDF.render("submission", data)
    end

    test "renders the points under a question of a returned exam" do
      question = %{
        "type" => "heading",
        "attrs" => %{"level" => 3, "partId" => "q-1", "points" => "2.5/4"},
        "content" => [%{"type" => "text", "text" => "Frage 1"}]
      }

      data = submission_data([%{"key" => "content", "heading" => nil, "doc" => doc([question])}])

      assert {:ok, "%PDF" <> _} = PDF.render("submission", data)
    end

    test "renders the paper version, with and without ruled pages" do
      assert {:ok, "%PDF" <> _} = PDF.render("paper", paper_data(kitchen_sink_doc()))

      assert {:ok, "%PDF" <> _} =
               PDF.render(
                 "paper",
                 paper_data(doc([]), max_points: nil, free_document: true, lined_pages: 4)
               )
    end

    test "survives deeply nested documents" do
      data =
        submission_data([%{"key" => "content", "heading" => nil, "doc" => deeply_nested_doc(25)}])

      assert {:ok, "%PDF" <> _} = PDF.render("submission", data)
    end

    test "sets every text in Nunito, code aside" do
      # Typst silently falls back to its bundled fonts when a family is
      # missing from priv/typst/fonts, so a renamed or deleted file would
      # otherwise only show up as a PDF that looks slightly off.
      data =
        submission_data([
          %{"key" => "sample", "heading" => "Musterlösung", "doc" => kitchen_sink_doc()}
        ])

      for {template, data} <- [{"submission", data}, {"paper", paper_data(kitchen_sink_doc())}] do
        {:ok, pdf} = PDF.render(template, data)

        fonts =
          ~r|/BaseFont\s*/[A-Z]{6}\+([A-Za-z0-9-]+)|
          |> Regex.scan(pdf, capture: :all_but_first)
          |> List.flatten()
          |> Enum.reject(&String.starts_with?(&1, "DejaVuSansMono"))

        assert "Nunito-Regular" in fonts
        assert Enum.all?(fonts, &String.starts_with?(&1, "Nunito-")), inspect(fonts)
      end
    end

    test "renders an empty submission" do
      assert {:ok, "%PDF" <> _} = PDF.render("submission", submission_data([]))
    end

    test "renders a submission with the 6 threshold and without a total" do
      data = %{submission_data([]) | "six_hint" => "6 ab 18"}
      assert {:ok, "%PDF" <> _} = PDF.render("submission", data)
      assert {:ok, "%PDF" <> _} = PDF.render("submission", %{data | "max_points" => nil})
    end

    test "treats document text as text, never as Typst markup" do
      hostile = ~s|#panic("boom") ] ) } $x$ <%= System.halt() %> #import "/paper.typ"|
      data = paper_data(doc([paragraph([text(hostile)])]))

      assert {:ok, "%PDF" <> _} = PDF.render("paper", data)
    end

    test "embeds images, and renders a placeholder for one that is gone" do
      png = png()

      read = fn
        "/uploads/exams/1/a.png" -> {:ok, {png, ".png"}}
        _other -> {:error, :not_found}
      end

      data =
        paper_data(
          doc([
            image("/uploads/exams/1/a.png"),
            paragraph([text("inline "), image("/uploads/exams/1/gone.png")])
          ])
        )

      assert {:ok, "%PDF" <> _} = PDF.render("paper", data, read_image: read)
    end
  end
end
