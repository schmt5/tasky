defmodule TaskyWeb.ExamCorrectionPartLiveTest do
  @moduledoc """
  The single correction page: the editor on the left, the power panel with the
  answer rows on the right, without a dialog to open first.
  """
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams

  @content %{
    "type" => "doc",
    "content" => [
      %{
        "type" => "heading",
        "attrs" => %{"level" => 3, "partId" => "q-1"},
        "content" => [%{"type" => "text", "text" => "Übersetzung"}]
      },
      %{
        "type" => "answerBlock",
        "attrs" => %{"answerId" => "a1"},
        "content" => [%{"type" => "paragraph"}]
      }
    ]
  }

  setup do
    teacher = user_fixture(%{role: "teacher"})
    %{teacher: teacher, scope: user_scope_fixture(teacher)}
  end

  defp open(conn, teacher, exam, submission, part_id) do
    conn
    |> log_in_user(teacher)
    |> live(~p"/exams/#{exam}/correction/#{submission}/parts/#{part_id}")
  end

  test "the answer rows are judged in the panel beside the editor", %{conn: conn} = ctx do
    exam = exam_fixture(scope: ctx.scope, status: "running", attrs: %{content: @content})
    # The rows come from the submitted document.
    {:ok, submission} =
      exam |> exam_submission_fixture() |> Exams.update_exam_submission_content(@content)

    {:ok, view, _html} = open(conn, ctx.teacher, exam, submission, "q-1")

    assert has_element?(view, "#power-panel #power-rows [data-power-row]")
    assert has_element?(view, "#power-keys-legend")
    # Points come from the rows here, so there are no Max / 0 shortcuts.
    refute has_element?(view, "#points-max")
  end

  test "without answer fields the points go in by hand", %{conn: conn} = ctx do
    exam = exam_fixture(scope: ctx.scope, status: "running", answer_mode: "free_document")
    submission = exam_submission_fixture(exam)

    {:ok, view, _html} =
      open(conn, ctx.teacher, exam, submission, Exams.free_document_part_id())

    refute has_element?(view, "#power-rows")
    assert has_element?(view, "#part-points-input")
    assert has_element?(view, "#points-max")
    assert has_element?(view, "#points-zero")
  end

  test "the done badge follows the toggle", %{conn: conn} = ctx do
    exam = exam_fixture(scope: ctx.scope, status: "running", attrs: %{content: @content})
    submission = exam_submission_fixture(exam)

    {:ok, view, _html} = open(conn, ctx.teacher, exam, submission, "q-1")

    refute has_element?(view, "#power-corrected-badge")

    view |> element("#power-toggle-corrected") |> render_click()

    assert has_element?(view, "#power-corrected-badge")
    assert has_element?(view, ~s|#power-toggle-corrected[aria-pressed="true"]|)
  end
end
