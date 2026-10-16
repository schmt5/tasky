defmodule Tasky.Correction.ChoiceTest do
  @moduledoc """
  Single-Choice-Radios (`choice`): alle Radios mit derselben `groupId` sind
  eine Frage, auch wenn sie in verschiedenen Tabellenzellen stehen. Jeder
  Walker zählt eine Gruppe einmal, an der Position ihres ersten Radios.
  """
  use ExUnit.Case, async: true

  alias Tasky.AI.NodePatcher
  alias Tasky.Correction.AnswerKey
  alias Tasky.Correction.Choice
  alias Tasky.Correction.SolutionHints
  alias Tasky.Correction.StringComparator
  alias Tasky.ExamDoc
  alias Tasky.ExamPaper
  alias Tasky.TiptapMarkdown

  defp radio(gid, oid, checked) do
    %{
      "type" => "choice",
      "attrs" => %{"groupId" => gid, "optionId" => oid, "checked" => checked}
    }
  end

  defp text(t), do: %{"type" => "text", "text" => t}
  defp para(content), do: %{"type" => "paragraph", "content" => content}
  defp cell(type, content), do: %{"type" => type, "content" => [para(content)]}

  # "Beispiel | analog | digital", one radio group per row.
  defp row(label, gid, choice) do
    %{
      "type" => "tableRow",
      "content" => [
        cell("tableCell", [text(label)]),
        cell("tableCell", [radio(gid, "#{gid}-a", choice == :analog)]),
        cell("tableCell", [radio(gid, "#{gid}-d", choice == :digital)])
      ]
    }
  end

  # An answer field, a table with two groups, and a group of two lines.
  defp nodes(thermo, sanduhr, city) do
    [
      %{
        "type" => "answerBlock",
        "attrs" => %{"answerId" => "a1"},
        "content" => [para([text("frei")])]
      },
      %{
        "type" => "table",
        "content" => [
          %{
            "type" => "tableRow",
            "content" => [
              cell("tableHeader", [text("Beispiel")]),
              cell("tableHeader", [text("analog")]),
              cell("tableHeader", [text("digital")])
            ]
          },
          row("Thermometer", "g1", thermo),
          row("Sanduhr", "g2", sanduhr)
        ]
      },
      para([text("Hauptstadt der Schweiz?")]),
      para([radio("g3", "g3-bern", city == :bern), text(" Bern")]),
      para([radio("g3", "g3-zh", city == :zh), text(" Zürich")])
    ]
  end

  defp doc(thermo, sanduhr, city),
    do: %{"type" => "doc", "content" => nodes(thermo, sanduhr, city)}

  defp radios(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &radios/1)
  defp radios(%{"type" => "choice"} = node), do: [node]
  defp radios(%{"content" => content}), do: radios(content)
  defp radios(_), do: []

  describe "groups/1" do
    test "labels an option by its column header, or by the text after it" do
      groups = Choice.groups(nodes(:analog, nil, :bern))

      assert Enum.map(groups["g1"].options, & &1.label) == ["analog", "digital"]
      assert Enum.map(groups["g3"].options, & &1.label) == ["Bern", "Zürich"]
      assert Choice.selected_label(groups["g1"]) == "analog"
      assert Choice.selected_label(groups["g2"]) == ""
    end
  end

  describe "AnswerKey" do
    test "stores the chosen option per group and blanks every radio" do
      {blanked, answers} = AnswerKey.split(doc(:digital, nil, :zh))

      assert answers["g1"] == "g1-d"
      assert answers["g2"] == nil
      assert answers["g3"] == "g3-zh"
      assert blanked |> Map.get("content") |> radios() |> Enum.all?(&(not Choice.checked?(&1)))
    end

    test "merge restores the chosen radio" do
      {blanked, answers} = AnswerKey.split(doc(:digital, :analog, :bern))

      assert AnswerKey.merge(blanked, answers) == doc(:digital, :analog, :bern)
    end

    test "block_ids carry the group ids" do
      ids = AnswerKey.block_ids(doc(nil, nil, nil))
      assert MapSet.subset?(MapSet.new(["a1", "g1", "g2", "g3"]), ids)
    end
  end

  describe "NodePatcher" do
    test "lists each group once, at its first radio, with the chosen label" do
      blocks = NodePatcher.list_answer_blocks(nodes(:analog, nil, :zh))

      assert [
               %{index: 0, type: "answerBlock"},
               %{
                 index: 1,
                 type: "choice",
                 answer_id: "g1",
                 text: "analog",
                 checked: nil,
                 group: nil
               },
               %{index: 2, type: "choice", answer_id: "g2", text: ""},
               %{index: 3, type: "choice", answer_id: "g3", text: "Zürich"}
             ] = blocks
    end

    test "annotate gives a group's radios one id and counts it once" do
      {annotated, count} = NodePatcher.annotate(nodes(nil, nil, nil))

      assert count == 4

      assert annotated |> radios() |> Enum.map(&get_in(&1, ["attrs", "__ai_id"])) ==
               ["2", "2", "3", "3", "4", "4"]
    end

    test "verdicts land on every radio of the group and read back" do
      {annotated, _} = NodePatcher.annotate(nodes(:analog, nil, nil))
      applied = NodePatcher.apply_verdicts(annotated, %{"2" => "correct", "3" => "wrong"})

      assert applied |> radios() |> Enum.map(&get_in(&1, ["attrs", "verdict"])) ==
               ["correct", "correct", "wrong", "wrong", nil, nil]

      refute applied |> radios() |> Enum.any?(&Map.has_key?(&1["attrs"], "__ai_id"))

      blocks = NodePatcher.list_answer_blocks(applied)
      assert Enum.map(blocks, & &1.inferred_verdict) == [nil, "correct", "wrong", nil]

      cleared = NodePatcher.rewrite_markers(applied, %{2 => "half"})

      assert cleared |> radios() |> Enum.map(&get_in(&1, ["attrs", "verdict"])) ==
               [nil, nil, "half", "half", nil, nil]
    end
  end

  describe "StringComparator.correct_part/4" do
    defp correct(student, sample) do
      {annotated, _} = NodePatcher.annotate(student)
      {:ok, %{verdicts: verdicts}} = StringComparator.correct_part(annotated, sample, 4)
      verdicts
    end

    test "a group is right only with exactly the sample's option" do
      sample = nodes(:analog, :digital, :bern)
      verdicts = correct(nodes(:analog, :analog, nil), sample)

      assert verdicts["2"] == "correct"
      assert verdicts["3"] == "wrong"
      assert verdicts["4"] == "wrong"
    end

    test "two chosen radios (crafted, the editor prevents it) are wrong" do
      [a1, table | rest] = nodes(nil, nil, :bern)
      both = Enum.map(rest, &put_in_radios(&1, true))

      verdicts = correct([a1, table | both], nodes(nil, nil, :bern))
      assert verdicts["4"] == "wrong"
    end

    test "a group whose sample chooses nothing gets no verdict" do
      verdicts = correct(nodes(:analog, nil, nil), nodes(nil, nil, nil))

      refute Map.has_key?(verdicts, "2")
      refute Map.has_key?(verdicts, "4")
    end
  end

  defp put_in_radios(
         %{"type" => "paragraph", "content" => [%{"type" => "choice"} = r | t]},
         checked
       ),
       do: para([put_in(r, ["attrs", "checked"], checked) | t])

  defp put_in_radios(node, _checked), do: node

  describe "SolutionHints.annotate/3" do
    test "puts the group's verdict on each radio and marks the right one" do
      annotated =
        SolutionHints.annotate(
          doc(:digital, nil, nil),
          %{"g1" => "g1-a"},
          %{"g1" => "wrong"}
        )

      [analog, digital | _] = annotated |> Map.get("content") |> radios()

      assert analog["attrs"]["verdict"] == "wrong"
      assert analog["attrs"]["correct"] == true
      assert digital["attrs"]["verdict"] == "wrong"
      refute Map.has_key?(digital["attrs"], "correct")
    end
  end

  describe "ExamDoc.answer_block_labels/1" do
    test "a table group is labelled by its row, a line group by the text before it" do
      labels = ExamDoc.answer_block_labels(nodes(nil, nil, nil))

      assert labels == %{
               0 => nil,
               1 => "Thermometer",
               2 => "Sanduhr",
               3 => "Hauptstadt der Schweiz?"
             }
    end
  end

  describe "separate_by_part/3" do
    test "a group spanning two questions is split at the question" do
      heading = fn id ->
        %{"type" => "heading", "attrs" => %{"level" => 3, "partId" => id}, "content" => []}
      end

      doc = %{
        "type" => "doc",
        "content" => [
          heading.("q-1"),
          para([radio("g", "o1", false)]),
          heading.("q-2"),
          para([radio("g", "o2", false)]),
          para([radio("g", "o3", false)])
        ]
      }

      separated = Choice.separate_by_part(doc, &ExamDoc.question_heading?/1, MapSet.new(["g"]))

      [first, second, third] =
        separated |> Map.get("content") |> radios() |> Enum.map(&Choice.group_id/1)

      assert first == "g"
      assert second != "g"
      assert second == third
    end
  end

  describe "paper and markdown" do
    test "paper prints every radio unchosen" do
      content = %{
        "type" => "doc",
        "content" => [
          %{"type" => "heading", "attrs" => %{"level" => 3, "partId" => "q-1"}, "content" => []}
          | nodes(:analog, :digital, :bern)
        ]
      }

      paper = ExamPaper.paper_doc(content, answer_mode: "answer_fields")

      refute paper |> Map.get("content") |> radios() |> Enum.any?(&Choice.checked?/1)
    end

    test "markdown shows radios as (x) and ( )" do
      markdown = TiptapMarkdown.to_markdown(doc(nil, nil, :bern))

      assert markdown =~ "(x)  Bern"
      assert markdown =~ "( )  Zürich"
    end
  end
end
