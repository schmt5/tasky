defmodule Tasky.ExamsCheckboxGroupsTest do
  @moduledoc """
  Checkboxes of one list belong together: the correction shows them as one
  question, with what was ticked next to what the sample solution ticks.
  """
  use TaskyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures

  alias Tasky.AI.NodePatcher
  alias Tasky.Exams

  defp task_item(id, label, checked) do
    %{
      "type" => "taskItem",
      "attrs" => %{"answerId" => id, "checked" => checked},
      "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => label}]}]
    }
  end

  # q-1: one free-text field, then a list of three checkboxes.
  defp doc(checked) do
    [a, b, c] = checked

    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "heading",
          "attrs" => %{"level" => 3, "partId" => "q-1"},
          "content" => [%{"type" => "text", "text" => "Frage 1"}]
        },
        %{
          "type" => "answerBlock",
          "attrs" => %{"answerId" => "t1"},
          "content" => [%{"type" => "paragraph"}]
        },
        %{
          "type" => "taskList",
          "content" => [
            task_item("c1", "Bern", a),
            task_item("c2", "Zürich", b),
            task_item("c3", "Genf", c)
          ]
        }
      ]
    }
  end

  defp part_nodes(doc),
    do: doc |> Exams.split_content_into_parts("answer_fields") |> hd() |> Map.fetch!(:nodes)

  # Solution: only "Bern" is ticked.
  defp setup_exam do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)

    {:ok, exam} =
      Exams.create_exam(scope, %{
        name: "Hauptstädte",
        content: doc([false, false, false]),
        sample_solution_points: %{"q-1" => 4}
      })

    {:ok, exam} =
      Exams.save_sample_solution_part(scope, exam, "q-1", part_nodes(doc([true, false, false])))

    {:ok, exam} = Exams.open_exam_session(:system, exam, "anonymous")
    {:ok, exam} = Exams.update_exam_status(:system, exam, "running")

    %{teacher: teacher, scope: scope, exam: exam}
  end

  defp submit(exam, email, checked) do
    {:ok, submission} =
      Exams.create_exam_submission(exam, %{
        "firstname" => email,
        "lastname" => "Test",
        "email" => "#{email}@example.com"
      })

    {:ok, submission} = Exams.update_exam_submission_content(submission, doc(checked))
    submission
  end

  describe "NodePatcher.list_answer_blocks/1" do
    test "reports each checkbox's tick and the list it belongs to" do
      blocks = NodePatcher.list_answer_blocks(part_nodes(doc([true, false, true])))

      assert [
               %{type: "answerBlock", checked: nil, group: nil},
               %{type: "taskItem", text: "Bern", checked: true, group: 1},
               %{type: "taskItem", text: "Zürich", checked: false, group: 1},
               %{type: "taskItem", text: "Genf", checked: true, group: 1}
             ] = blocks
    end
  end

  describe "list_part_answer_groups/2" do
    test "groups checkbox answers by tick, not by label" do
      %{exam: exam} = setup_exam()
      submit(exam, "anna", [true, false, false])
      submit(exam, "ben", [false, true, false])

      [_text, bern, zuerich, _genf] = Exams.list_part_answer_groups(exam, "q-1")

      assert bern.type == "taskItem"
      assert bern.label == "Bern"
      assert bern.sample_answers == ["angekreuzt"]

      groups = Map.new(bern.groups, &{&1.text, &1})
      assert groups["angekreuzt"].default_verdict == "correct"
      assert groups["nicht angekreuzt"].default_verdict == "wrong"
      assert groups["angekreuzt"].count == 1

      assert zuerich.sample_answers == ["nicht angekreuzt"]
      zgroups = Map.new(zuerich.groups, &{&1.text, &1})
      assert zgroups["nicht angekreuzt"].default_verdict == "correct"
      assert zgroups["angekreuzt"].default_verdict == "wrong"
    end
  end

  describe "list_part_answer_blocks/3" do
    test "pairs each tick with the sample solution's" do
      %{exam: exam} = setup_exam()
      submission = submit(exam, "anna", [false, true, false])

      checkboxes =
        exam
        |> Exams.list_part_answer_blocks(submission, "q-1")
        |> Enum.filter(&(&1.type == "taskItem"))

      assert Enum.map(checkboxes, &{&1.checked, &1.expected_checked}) ==
               [{false, true}, {true, false}, {false, false}]
    end
  end

  describe "correction views" do
    test "the power view shows the checkboxes as one group with both ticks", %{conn: conn} do
      %{teacher: teacher, exam: exam} = setup_exam()
      submission = submit(exam, "anna", [false, true, false])

      {:ok, view, _html} =
        conn
        |> log_in_user(teacher)
        |> live(~p"/exams/#{exam}/correction/#{submission}/parts/q-1?power=1")

      group = view |> element("#power-checkbox-group-1") |> render()

      assert group =~ "Bern"
      assert group =~ "Zürich"
      assert group =~ "Genf"
      assert group =~ "Lösung: ankreuzen"
      assert group =~ "Lösung: leer lassen"
      assert group =~ ~s(aria-label="angekreuzt")
      assert group =~ ~s(aria-label="nicht angekreuzt")
      assert group =~ "1 von 3 wie in der Musterlösung"
    end

    test "the bulk view groups the checkboxes of one list", %{conn: conn} do
      %{teacher: teacher, exam: exam} = setup_exam()
      submit(exam, "anna", [true, false, false])

      {:ok, view, _html} =
        conn
        |> log_in_user(teacher)
        |> live(~p"/exams/#{exam}/correction/bulk/q-1")

      group = view |> element("#bulk-checkbox-group-1") |> render()

      assert group =~ "Checkboxen · 3 Stück"
      assert group =~ "Bern → angekreuzt"
      assert group =~ "Zürich → nicht angekreuzt"
    end
  end
end
