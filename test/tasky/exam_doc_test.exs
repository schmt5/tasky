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

  describe "split_content_into_parts/2 — answer_fields" do
    test "prefers the stable partId and falls back to positional ids" do
      d =
        doc([
          %{"type" => "paragraph"},
          heading("Erste", %{"partId" => "q-abc"}),
          %{"type" => "paragraph"},
          heading("Zweite")
        ])

      assert [%{id: "q-abc", label: "Erste"}, %{id: "q-2", label: "Zweite"}] =
               ExamDoc.split_content_into_parts(d, "answer_fields")
    end

    test "a callout following a heading belongs to that part" do
      callout = %{
        "type" => "callout",
        "attrs" => %{"color" => "yellow"},
        "content" => [%{"type" => "paragraph"}]
      }

      d = doc([heading("Frage", %{"partId" => "q-a"}), callout])

      assert [%{id: "q-a", nodes: nodes}] = ExamDoc.split_content_into_parts(d, "answer_fields")
      assert callout in nodes
    end

    # Splitting only looks at TOP-LEVEL headings, so a question wrapped in a
    # callout disappears from the part list — which would make
    # Exams.prune_orphan_block_points drop that part's block points. The editor
    # prevents creating this shape (setCallout refuses a selection with an h3);
    # this test pins the server-side behaviour it protects against.
    test "a heading nested inside a callout yields no parts" do
      d =
        doc([
          %{
            "type" => "callout",
            "attrs" => %{"color" => "red"},
            "content" => [heading("Frage", %{"partId" => "q-a"})]
          }
        ])

      assert ExamDoc.split_content_into_parts(d, "answer_fields") == []
    end

    test "reordering keeps part ids attached to their headings" do
      h1 = heading("Erste", %{"partId" => "q-one"})
      h2 = heading("Zweite", %{"partId" => "q-two"})

      assert [%{id: "q-one"}, %{id: "q-two"}] =
               ExamDoc.split_content_into_parts(doc([h1, h2]), "answer_fields")

      assert [%{id: "q-two"}, %{id: "q-one"}] =
               ExamDoc.split_content_into_parts(doc([h2, h1]), "answer_fields")
    end
  end

  describe "split_content_into_parts/2 — horizontal rules" do
    defp rule, do: %{"type" => "horizontalRule"}

    defp para(text),
      do: %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}

    defp section(text) do
      %{
        "type" => "heading",
        "attrs" => %{"level" => 2},
        "content" => [%{"type" => "text", "text" => text}]
      }
    end

    defp split(d) do
      {ExamDoc.content_preamble(d, "answer_fields"),
       ExamDoc.split_content_into_parts(d, "answer_fields")}
    end

    defp nodes_of(parts), do: Map.new(parts, &{&1.id, &1.nodes})

    test "a rule hands the section after it to the next question" do
      q1 = heading("Erste", %{"partId" => "q-1"})
      q2 = heading("Zweite", %{"partId" => "q-2"})
      d = doc([q1, para("A1"), rule(), section("Teil B"), para("Kontext"), q2, para("A2")])

      {[], parts} = split(d)

      assert [%{id: "q-1", label: "Erste"}, %{id: "q-2", label: "Zweite"}] = parts

      assert nodes_of(parts) == %{
               "q-1" => [q1, para("A1")],
               "q-2" => [rule(), section("Teil B"), para("Kontext"), q2, para("A2")]
             }
    end

    test "a rule with no question after it stays with the question before" do
      q1 = heading("Erste", %{"partId" => "q-1"})
      d = doc([q1, rule(), para("Schluss")])

      assert {[], [%{id: "q-1", nodes: [^q1, %{"type" => "horizontalRule"}, _]}]} = split(d)
    end

    test "only the last of two rules opens the lead-in" do
      q1 = heading("Erste", %{"partId" => "q-1"})
      q2 = heading("Zweite", %{"partId" => "q-2"})
      d = doc([q1, rule(), para("noch 1"), rule(), para("zu 2"), q2])

      {[], parts} = split(d)

      assert nodes_of(parts) == %{
               "q-1" => [q1, rule(), para("noch 1")],
               "q-2" => [rule(), para("zu 2"), q2]
             }
    end

    test "a rule in the intro ends the preamble" do
      q1 = heading("Erste", %{"partId" => "q-1"})
      d = doc([para("Intro"), rule(), para("zu 1"), q1])

      assert {[%{"type" => "paragraph"}], [%{id: "q-1", nodes: [_rule, _para, ^q1]}]} = split(d)
    end

    test "a rule without any question is preamble" do
      d = doc([para("A"), rule(), para("B")])

      assert {preamble, []} = split(d)
      assert preamble == d["content"]
    end

    test "a rule right before a question splits like no rule at all" do
      q1 = heading("Erste", %{"partId" => "q-1"})
      q2 = heading("Zweite", %{"partId" => "q-2"})

      {[], parts} = split(doc([q1, para("A1"), rule(), q2]))

      assert nodes_of(parts) == %{"q-1" => [q1, para("A1")], "q-2" => [rule(), q2]}
    end

    test "assemble restores every shape" do
      q1 = heading("Erste", %{"partId" => "q-1"})
      q2 = heading("Zweite", %{"partId" => "q-2"})

      for nodes <- [
            [para("Intro"), rule(), q1, rule(), section("B"), q2, rule(), para("Ende")],
            [rule(), rule(), q1, para("x"), rule(), rule(), q2],
            [para("nur Text"), rule()]
          ] do
        d = doc(nodes)
        {preamble, parts} = split(d)
        assert ExamDoc.assemble_parts_into_content(preamble, parts) == d
      end
    end
  end

  describe "split_content_into_parts/2 — free_document" do
    test "the whole document is one part under the fixed id" do
      d =
        doc([
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Aufgabe"}]},
          %{"type" => "paragraph"}
        ])

      assert [%{id: id, label: "Dokument", nodes: nodes}] =
               ExamDoc.split_content_into_parts(d, "free_document")

      assert id == ExamDoc.free_document_part_id()
      assert nodes == d["content"]
    end

    test "an h3 does not split the document" do
      d = doc([heading("Sieht aus wie eine Frage"), %{"type" => "paragraph"}])

      assert [%{nodes: nodes}] = ExamDoc.split_content_into_parts(d, "free_document")
      assert length(nodes) == 2
    end

    test "an empty document still yields exactly one part" do
      assert [%{nodes: []}] = ExamDoc.split_content_into_parts(%{}, "free_document")
    end

    test "the preamble is empty, so assemble stays the inverse of split" do
      d =
        doc([
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Aufgabe"}]},
          heading("Zwischentitel")
        ])

      parts = ExamDoc.split_content_into_parts(d, "free_document")
      preamble = ExamDoc.content_preamble(d, "free_document")

      assert preamble == []
      assert ExamDoc.assemble_parts_into_content(preamble, parts) == d
    end
  end

  test "assemble is the inverse of split + preamble" do
    d =
      doc([
        %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Intro"}]},
        heading("Frage", %{"partId" => "q-x"}),
        %{"type" => "paragraph"}
      ])

    parts = ExamDoc.split_content_into_parts(d, "answer_fields")
    preamble = ExamDoc.content_preamble(d, "answer_fields")

    assert ExamDoc.assemble_parts_into_content(preamble, parts) == d
  end
end
