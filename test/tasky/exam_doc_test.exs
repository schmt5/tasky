defmodule Tasky.ExamDocTest do
  use ExUnit.Case, async: true

  alias Tasky.ExamDoc

  defp heading(text, attrs \\ %{}) do
    %{
      "type" => "heading",
      "attrs" => Map.merge(%{"level" => 3}, attrs),
      "content" => [%{"type" => "text", "text" => text}]
    }
  end

  defp doc(nodes), do: %{"type" => "doc", "content" => nodes}

  describe "ensure_part_ids/1" do
    test "assigns ids only to headings that lack one" do
      d = doc([heading("A", %{"partId" => "q-keep"}), heading("B")])

      %{"content" => [a, b]} = ExamDoc.ensure_part_ids(d)

      assert a["attrs"]["partId"] == "q-keep"
      assert is_binary(b["attrs"]["partId"])
      assert b["attrs"]["partId"] != "q-keep"
    end

    test "is idempotent" do
      once = ExamDoc.ensure_part_ids(doc([heading("A")]))
      assert ExamDoc.ensure_part_ids(once) == once
    end
  end

  describe "split_content_into_parts/1" do
    test "prefers the stable partId and falls back to positional ids" do
      d =
        doc([
          %{"type" => "paragraph"},
          heading("Erste", %{"partId" => "q-abc"}),
          %{"type" => "paragraph"},
          heading("Zweite")
        ])

      assert [%{id: "q-abc", label: "Erste"}, %{id: "q-2", label: "Zweite"}] =
               ExamDoc.split_content_into_parts(d)
    end

    test "reordering keeps part ids attached to their headings" do
      h1 = heading("Erste", %{"partId" => "q-one"})
      h2 = heading("Zweite", %{"partId" => "q-two"})

      assert [%{id: "q-one"}, %{id: "q-two"}] =
               ExamDoc.split_content_into_parts(doc([h1, h2]))

      assert [%{id: "q-two"}, %{id: "q-one"}] =
               ExamDoc.split_content_into_parts(doc([h2, h1]))
    end
  end

  test "assemble is the inverse of split + preamble" do
    d =
      doc([
        %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Intro"}]},
        heading("Frage", %{"partId" => "q-x"}),
        %{"type" => "paragraph"}
      ])

    parts = ExamDoc.split_content_into_parts(d)
    preamble = ExamDoc.content_preamble(d)

    assert ExamDoc.assemble_parts_into_content(preamble, parts) == d
  end
end
