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

    test "the bulk view groups the checkboxes of one list by answer pattern", %{conn: conn} do
      %{teacher: teacher, exam: exam} = setup_exam()
      submit(exam, "anna", [true, false, false])
      submit(exam, "ben", [true, false, false])
      submit(exam, "cara", [false, true, false])

      {:ok, view, _html} = open_bulk(conn, teacher, exam)

      assert has_element?(view, "#bulk-checkbox-solution-1")
      # Anna and Ben ticked like the solution, Cara swapped Bern for Zürich.
      assert view |> element("#bulk-pattern-1-100") |> render() =~ "entspricht der Lösung"
      assert view |> element("#bulk-pattern-1-100") |> render() =~ "2× abgegeben"

      cara = view |> element("#bulk-pattern-1-010") |> render()
      assert cara =~ "1× abgegeben"
      assert cara =~ "fehlt"
      assert cara =~ "zu viel angekreuzt"
      assert cara =~ "1 / 3 P."
      refute cara =~ "entspricht der Lösung"
    end

    test "a pattern verdict judges every checkbox of the pattern at once", %{conn: conn} do
      %{teacher: teacher, exam: exam} = setup_exam()
      anna = submit(exam, "anna", [true, false, false])
      cara = submit(exam, "cara", [false, true, false])

      {:ok, view, _html} = open_bulk(conn, teacher, exam)

      view
      |> element("#bulk-pattern-1-010 button[phx-value-verdict=correct]")
      |> render_click()

      assert verdicts(exam, cara) == %{"c1" => "correct", "c2" => "correct", "c3" => "correct"}
      assert verdicts(exam, anna) == %{}
      assert view |> element("#bulk-pattern-1-010") |> render() =~ "3 / 3 P."

      # Pressing the active verdict again hands the pattern back to the defaults.
      view
      |> element("#bulk-pattern-1-010 button[phx-value-verdict=correct]")
      |> render_click()

      assert verdicts(exam, cara) == %{}
    end

    test "a click on one checkbox of a pattern flips just that checkbox", %{conn: conn} do
      %{teacher: teacher, exam: exam} = setup_exam()
      anna = submit(exam, "anna", [true, false, false])

      {:ok, view, _html} = open_bulk(conn, teacher, exam)

      view |> element("#bulk-pattern-option-1-100-2") |> render_click()
      assert verdicts(exam, anna) == %{"c2" => "wrong"}
      assert has_element?(view, ~s(#bulk-pattern-option-1-100-2[data-verdict="wrong"]))

      # Back on the default, nothing explicit is left behind.
      view |> element("#bulk-pattern-option-1-100-2") |> render_click()
      assert verdicts(exam, anna) == %{}
    end

    test "students of one pattern judged differently show the checkbox as mixed", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = setup_exam()
      anna = submit(exam, "anna", [true, false, false])
      submit(exam, "ben", [true, false, false])
      {:ok, _} = Exams.set_block_verdict(scope, anna, "q-1", 1, "wrong")

      {:ok, view, _html} = open_bulk(conn, teacher, exam)

      assert has_element?(view, ~s(#bulk-pattern-option-1-100-1[data-verdict="partial"]))
      assert view |> element("#bulk-pattern-option-1-100-1") |> render() =~ "uneinheitlich"
    end
  end

  describe "checkbox scoring rule" do
    test "equal shares stay on the 0.25 grid" do
      %{exam: exam} = setup_exam()

      blocks =
        exam.content |> part_nodes() |> NodePatcher.list_answer_blocks()

      # 4 points over 4 blocks is 1 each; 3 points over 4 would be 0.75 each.
      assert Exams.resolve_block_points(exam, "q-1", blocks) == %{0 => 1, 1 => 1, 2 => 1, 3 => 1}

      {:ok, exam} = Exams.set_sample_solution_part_points(:system, exam, "q-1", 1)
      shares = Exams.resolve_block_points(exam, "q-1", blocks)

      assert shares |> Map.values() |> Enum.sum() == 1
      assert Enum.all?(Map.values(shares), &(&1 * 4 == trunc(&1 * 4)))
    end

    test "changing the rule rescores everyone already graded", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = setup_exam()
      cara = submit(exam, "cara", [false, true, false])

      # Text field right; Bern and Zürich wrong, Genf right — 1 point each.
      {:ok, _} =
        Exams.set_block_verdicts_bulk(
          scope,
          exam,
          "q-1",
          %{0 => "correct", 1 => "wrong", 2 => "wrong", 3 => "correct"},
          [cara.id]
        )

      assert Exams.get_submission(exam, cara.id).points_per_part["q-1"] == 2

      {:ok, view, _html} =
        conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/content?tab=musterloesung")

      view |> element("#correction-options-btn-q-1") |> render_click()
      view |> element("#checkbox-scoring-all_or_nothing") |> render_click()

      view
      |> form("#correction-options-form-q-1", %{
        "options" => %{"checkbox_rule" => "all_or_nothing"}
      })
      |> render_submit()

      assert Exams.get_submission(exam, cara.id).points_per_part["q-1"] == 1

      {:ok, view, _html} = open_bulk(conn, teacher, exam)
      assert view |> element("#bulk-pattern-1-010") |> render() =~ "0 / 3 P."
    end

    test "manual points for a pattern are kept under all or nothing", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = setup_exam()
      cara = submit(exam, "cara", [false, true, false])

      {:ok, _} =
        Exams.update_ai_correction_config(scope, exam, "q-1", %{
          "checkbox_scoring" => "all_or_nothing"
        })

      {:ok, view, _html} = open_bulk(conn, teacher, exam)
      view |> element("#bulk-pattern-manual-1-010") |> render_click()

      view
      |> form("#bulk-pattern-manual-form-1-010", %{"points" => "2"})
      |> render_submit()

      assert Exams.get_submission(exam, cara.id).points_per_part["q-1"] == 2
      assert view |> element("#bulk-pattern-1-010") |> render() =~ "2 / 3 P."

      # Back to the rule: all or nothing, and Cara has two checkboxes wrong.
      view |> element("#bulk-pattern-reset-1-010") |> render_click()

      assert verdicts(exam, cara) == %{}
      assert view |> element("#bulk-pattern-1-010") |> render() =~ "0 / 3 P."
      refute has_element?(view, "#bulk-pattern-reset-1-010")
    end
  end

  defp open_bulk(conn, teacher, exam) do
    conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/correction/bulk/q-1")
  end

  defp verdicts(exam, submission),
    do: Exams.get_submission(exam, submission.id).block_verdicts || %{}
end
