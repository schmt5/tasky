defmodule TaskyWeb.ExamCorrectionOverviewLiveTest do
  @moduledoc """
  The correction overview lists one row per question with its status and a
  link into the bulk correction, and one column per participant.
  """
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams

  defp question(n) do
    [
      %{
        "type" => "heading",
        "attrs" => %{"level" => 3, "partId" => "q-#{n}"},
        "content" => [%{"type" => "text", "text" => "Übersetzung #{n}"}]
      },
      %{
        "type" => "answerBlock",
        "attrs" => %{"answerId" => "a#{n}"},
        "content" => [%{"type" => "paragraph"}]
      }
    ]
  end

  setup do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)
    content = %{"type" => "doc", "content" => Enum.flat_map(1..3, &question/1)}
    exam = exam_fixture(scope: scope, status: "running", attrs: %{content: content})
    first = exam_submission_fixture(exam)

    second =
      exam_submission_fixture(exam, %{"email" => "erika@example.com", "firstname" => "Erika"})

    # q-1 done for everyone, q-2 for one participant, q-3 untouched.
    for s <- [first, second], do: {:ok, _} = Exams.mark_part_corrected(scope, s, "q-1")
    {:ok, _} = Exams.mark_part_corrected(scope, first, "q-2")

    %{teacher: teacher, exam: exam, first: first, second: second}
  end

  defp open(conn, teacher, exam) do
    conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/correction")
  end

  test "one row per question with its status", %{conn: conn} = ctx do
    {:ok, view, _html} = open(conn, ctx.teacher, ctx.exam)

    assert has_element?(view, ~s|#correction-part-q-1[data-status="done"]|)
    assert has_element?(view, ~s|#correction-part-q-2[data-status="partial"]|)
    assert has_element?(view, ~s|#correction-part-q-3[data-status="open"]|)
  end

  test "each question links into its bulk correction", %{conn: conn} = ctx do
    {:ok, view, _html} = open(conn, ctx.teacher, ctx.exam)

    for n <- 1..3 do
      assert has_element?(
               view,
               ~s|#correction-action-q-#{n}[href="/exams/#{ctx.exam.id}/correction/bulk/q-#{n}"]|
             )
    end

    assert view |> element("#correction-action-q-1") |> render() =~ "Überprüfen"
    assert view |> element("#correction-action-q-2") |> render() =~ "Korrigieren"
    assert view |> element("#correction-action-q-3") |> render() =~ "Korrigieren"
  end

  test "one column per participant with the per-question state", %{conn: conn} = ctx do
    {:ok, view, _html} = open(conn, ctx.teacher, ctx.exam)

    for s <- [ctx.first, ctx.second] do
      assert has_element?(view, "#correction-participant-#{s.id}")
      assert has_element?(view, "#correction-total-#{s.id}")
    end

    first_q2 =
      ~s|#correction-part-q-2 a[href="/exams/#{ctx.exam.id}/correction/#{ctx.first.id}/parts/q-2"]|

    second_q2 =
      ~s|#correction-part-q-2 a[href="/exams/#{ctx.exam.id}/correction/#{ctx.second.id}/parts/q-2"]|

    assert has_element?(view, first_q2 <> ~s|[data-corrected="true"]|)
    assert has_element?(view, second_q2 <> ~s|[data-corrected="false"]|)
  end
end
