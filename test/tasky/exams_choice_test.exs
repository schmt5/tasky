defmodule Tasky.ExamsChoiceTest do
  @moduledoc """
  Single-Choice-Gruppen in einer Prüfung: eine Gruppe ist ein Block — ein
  Punkteanteil, ein Verdikt unter ihrer `groupId` —, die Korrektur zeigt die
  gewählte neben der richtigen Option.
  """
  use Tasky.DataCase, async: false

  import Tasky.AccountsFixtures

  alias Tasky.AI.NodePatcher
  alias Tasky.Correction.Choice
  alias Tasky.Correction.StringComparator
  alias Tasky.Exams

  defp radio(gid, oid, checked),
    do: %{
      "type" => "choice",
      "attrs" => %{"groupId" => gid, "optionId" => oid, "checked" => checked}
    }

  defp text(t), do: %{"type" => "text", "text" => t}
  defp para(content), do: %{"type" => "paragraph", "content" => content}
  defp cell(type, content), do: %{"type" => type, "content" => [para(content)]}

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

  # q-1: "analog oder digital?" for two examples, plus a line group.
  defp doc({thermo, sanduhr, city}) do
    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "heading",
          "attrs" => %{"level" => 3, "partId" => "q-1"},
          "content" => [text("Analog oder digital?")]
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
        para([radio("g3", "g3-bern", city == :bern), text(" Bern")]),
        para([radio("g3", "g3-zh", city == :zh), text(" Zürich")])
      ]
    }
  end

  defp part_nodes(doc),
    do: doc |> Exams.split_content_into_parts("answer_fields") |> hd() |> Map.fetch!(:nodes)

  # Solution: Thermometer digital, Sanduhr analog, Bern. 3 points → 1 per group.
  defp setup_exam do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)

    {:ok, exam} =
      Exams.create_exam(scope, %{
        name: "Analog / digital",
        content: doc({nil, nil, nil}),
        sample_solution_points: %{"q-1" => 3}
      })

    {:ok, exam} =
      Exams.save_sample_solution_part(
        scope,
        exam,
        "q-1",
        part_nodes(doc({:digital, :analog, :bern}))
      )

    {:ok, exam} = Exams.open_exam_session(:system, exam, "anonymous")
    {:ok, exam} = Exams.update_exam_status(:system, exam, "running")

    %{scope: scope, exam: exam}
  end

  defp submit(exam, name, answers) do
    {:ok, submission} =
      Exams.create_exam_submission(exam, %{
        "firstname" => name,
        "lastname" => "Test",
        "email" => "#{name}@example.com"
      })

    {:ok, submission} = Exams.update_exam_submission_content(submission, doc(answers))
    submission
  end

  # What `Tasky.AI.BulkCorrectionRunner` does for one submission and part.
  defp auto_correct(exam, submission) do
    nodes = part_nodes(Exams.correction_content(submission))
    sample = part_nodes(Exams.sample_solution_doc(exam))
    {annotated, _count} = NodePatcher.annotate(nodes)
    blocks = NodePatcher.list_answer_blocks(nodes)

    {:ok, %{verdicts: verdicts}} =
      StringComparator.correct_part(annotated, sample, 3, %{
        block_points: Exams.resolve_block_points(exam, "q-1", blocks)
      })

    by_answer_id =
      for {id, v} <- verdicts, into: %{} do
        {Enum.at(blocks, String.to_integer(id) - 1).answer_id, v}
      end

    {:ok, updated} =
      Exams.apply_auto_correction(
        :system,
        submission,
        "q-1",
        NodePatcher.apply_verdicts(annotated, verdicts),
        verdicts: by_answer_id
      )

    updated
  end

  test "the sample solution stores the chosen option per group" do
    %{exam: exam} = setup_exam()

    assert exam.sample_solution == %{"g1" => "g1-d", "g2" => "g2-a", "g3" => "g3-bern"}
  end

  test "a group is one block with one points share" do
    %{exam: exam} = setup_exam()
    blocks = NodePatcher.list_answer_blocks(part_nodes(exam.content))

    assert Enum.map(blocks, & &1.answer_id) == ["g1", "g2", "g3"]
    assert Exams.resolve_block_points(exam, "q-1", blocks) == %{0 => 1, 1 => 1, 2 => 1}
    assert Exams.checkbox_lists(exam, "q-1", blocks) == []
  end

  test "auto-correction gives one verdict per group" do
    %{exam: exam} = setup_exam()
    submission = submit(exam, "anna", {:digital, :digital, nil})

    updated = auto_correct(exam, submission)

    assert updated.block_verdicts == %{"g1" => "correct", "g2" => "wrong", "g3" => "wrong"}
    assert updated.points_per_part["q-1"] == 1
  end

  test "the correction lists the chosen next to the expected option" do
    %{exam: exam} = setup_exam()
    submission = submit(exam, "anna", {:analog, nil, :bern})

    blocks = Exams.list_part_answer_blocks(exam, submission, "q-1")

    assert Enum.map(blocks, &{&1.text, &1.expected_option}) == [
             {"analog", "digital"},
             {"", "analog"},
             {"Bern", "Bern"}
           ]
  end

  test "the grouped correction groups by the chosen option" do
    %{exam: exam} = setup_exam()
    submit(exam, "anna", {:digital, nil, nil})
    submit(exam, "ben", {:digital, nil, nil})
    submit(exam, "cleo", {:analog, nil, nil})

    [thermo | _] = Exams.list_part_answer_groups(exam, "q-1")

    assert thermo.type == "choice"
    assert thermo.label == "Thermometer"
    assert thermo.sample_answers == ["digital"]

    groups = Map.new(thermo.groups, &{&1.text, {&1.count, &1.default_verdict}})
    assert groups == %{"digital" => {2, "correct"}, "analog" => {1, "wrong"}}
  end

  test "saving the content keeps a group inside one question" do
    %{scope: scope, exam: exam} = setup_exam()

    content = %{
      "type" => "doc",
      "content" =>
        exam.content["content"] ++
          [
            %{
              "type" => "heading",
              "attrs" => %{"level" => 3, "partId" => "q-2"},
              "content" => [text("Frage 2")]
            },
            para([radio("g3", "g3-ge", false), text(" Genf")])
          ]
    }

    {:ok, saved} = Exams.save_exam_structure(scope, exam, content)

    [q1, q2] = Exams.split_content_into_parts(saved.content, "answer_fields")
    [g1, g2, g3] = q1.nodes |> NodePatcher.list_answer_blocks() |> Enum.map(& &1.answer_id)
    [moved] = q2.nodes |> NodePatcher.list_answer_blocks() |> Enum.map(& &1.answer_id)

    assert {g1, g2, g3} == {"g1", "g2", "g3"}
    refute moved == "g3"
    assert Map.has_key?(Choice.groups(q2.nodes), moved)
  end
end
