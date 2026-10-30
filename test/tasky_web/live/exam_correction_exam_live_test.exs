defmodule TaskyWeb.ExamCorrectionExamLiveTest do
  @moduledoc """
  The whole exam of one participant in the correction: every part to read,
  each opening its grading, and the way back from grading to the same part.
  """
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams

  @questions (for n <- 1..2 do
                [
                  %{
                    "type" => "heading",
                    "attrs" => %{"level" => 3, "partId" => "q-#{n}"},
                    "content" => [%{"type" => "text", "text" => "Frage #{n}"}]
                  },
                  %{
                    "type" => "answerBlock",
                    "attrs" => %{"answerId" => "a#{n}"},
                    "content" => [%{"type" => "paragraph"}]
                  }
                ]
              end)

  @content %{"type" => "doc", "content" => List.flatten(@questions)}

  setup do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)

    exam =
      exam_fixture(
        scope: scope,
        status: "running",
        attrs: %{content: @content, sample_solution_points: %{"q-1" => 2, "q-2" => 3}}
      )

    %{teacher: teacher, scope: scope, exam: exam}
  end

  defp participant(exam, firstname) do
    {:ok, submission} =
      exam
      |> exam_submission_fixture(%{
        "firstname" => firstname,
        "email" => "#{String.downcase(firstname)}@example.com"
      })
      |> Exams.update_exam_submission_content(@content)

    submission
  end

  defp open(conn, teacher, path) do
    conn
    |> log_in_user(teacher)
    |> live(path)
  end

  test "shows every part to read, each opening its grading", %{conn: conn} = ctx do
    submission = participant(ctx.exam, "Anna")

    {:ok, view, _html} =
      open(conn, ctx.teacher, ~p"/exams/#{ctx.exam}/correction/#{submission}")

    for part <- ["q-1", "q-2"] do
      assert has_element?(
               view,
               "#exam-part-#{part} #exam-part-viewer-#{submission.id}-#{part}[phx-hook='ExamReadOnlyPartViewer']"
             )

      grade_path = ~p"/exams/#{ctx.exam}/correction/#{submission}/parts/#{part}"
      assert has_element?(view, "#exam-part-grade-#{part}[href='#{grade_path}']")
      assert has_element?(view, "#exam-part-link-#{part}[href='#{grade_path}']")
    end

    assert has_element?(view, "#correction-mode-exam[aria-current='page']")

    assert has_element?(
             view,
             "#correction-mode-part[href='#{~p"/exams/#{ctx.exam}/correction/#{submission}/parts/q-1"}']"
           )
  end

  test "shows the points and the status of each part", %{conn: conn} = ctx do
    submission = participant(ctx.exam, "Anna")
    {:ok, submission} = Exams.set_part_points(ctx.scope, submission, "q-1", 1.5)
    {:ok, _} = Exams.mark_part_corrected(ctx.scope, submission, "q-1", %{})

    {:ok, view, _html} =
      open(conn, ctx.teacher, ~p"/exams/#{ctx.exam}/correction/#{submission}")

    assert view |> element("#exam-part-grade-q-1") |> render() =~ "Erledigt"
    assert view |> element("#exam-part-grade-q-2") |> render() =~ "Offen"
    assert view |> element("#correction-exam-panel") |> render() =~ "1 von 2 Teilen erledigt"
  end

  test "the arrows go to the neighbouring participant's whole exam", %{conn: conn} = ctx do
    anna = participant(ctx.exam, "Anna")
    ben = participant(ctx.exam, "Ben")

    {:ok, view, _html} = open(conn, ctx.teacher, ~p"/exams/#{ctx.exam}/correction/#{anna}")

    refute has_element?(view, "#exam-prev-participant")
    view |> element("#exam-next-participant") |> render_click()
    assert_patch(view, ~p"/exams/#{ctx.exam}/correction/#{ben}")
    assert has_element?(view, "#exam-part-viewer-#{ben.id}-q-1")
  end

  test "grading leads back to the whole exam at the same part", %{conn: conn} = ctx do
    submission = participant(ctx.exam, "Anna")

    {:ok, view, _html} =
      open(conn, ctx.teacher, ~p"/exams/#{ctx.exam}/correction/#{submission}/parts/q-2")

    back = ~p"/exams/#{ctx.exam}/correction/#{submission}?#{[part: "q-2"]}"
    assert has_element?(view, "#correction-mode-exam[href='#{back}']")
    assert has_element?(view, "nav a[href='#{back}']", "Anna")
  end

  test "the progress grid and the correction overview lead to it", %{conn: conn} = ctx do
    submission = participant(ctx.exam, "Anna")
    path = ~p"/exams/#{ctx.exam}/correction/#{submission}"
    conn = log_in_user(conn, ctx.teacher)

    {:ok, progress, _html} = live(conn, ~p"/exams/#{ctx.exam}/cockpit/progress")
    assert has_element?(progress, "#participant-link-#{submission.id}[href='#{path}']")

    assert has_element?(
             progress,
             "#cell-#{submission.id}-q-2[href='#{path}/parts/q-2']"
           )

    {:ok, correction, _html} = live(conn, ~p"/exams/#{ctx.exam}/correction")

    assert has_element?(
             correction,
             "#correction-participant-link-#{submission.id}[href='#{path}']"
           )
  end

  test "is not open to another teacher", %{conn: conn} = ctx do
    submission = participant(ctx.exam, "Anna")
    other = user_fixture(%{role: "teacher"})

    assert_raise Ecto.NoResultsError, fn ->
      open(conn, other, ~p"/exams/#{ctx.exam}/correction/#{submission}")
    end
  end
end
