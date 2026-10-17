defmodule TaskyWeb.ExamCorrectionBulkOrderLiveTest do
  @moduledoc """
  The bulk correction lists answers best-first — full points, partial points,
  zero, "keine Antwort" — and holds that order while the teacher grades, so a
  judged card does not jump away; reopening the question sorts again.
  """
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures

  alias Tasky.Exams

  defp doc(answer) do
    paragraph =
      case answer do
        nil -> %{"type" => "paragraph"}
        text -> %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}
      end

    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "heading",
          "attrs" => %{"level" => 3, "partId" => "q-1"},
          "content" => [%{"type" => "text", "text" => "Übersetze «fliegen»"}]
        },
        %{"type" => "answerBlock", "attrs" => %{"answerId" => "a1"}, "content" => [paragraph]}
      ]
    }
  end

  defp submit(exam, name, answer) do
    {:ok, submission} =
      Exams.create_exam_submission(exam, %{
        "firstname" => name,
        "lastname" => "Test",
        "email" => "#{name}@example.com"
      })

    {:ok, submission} = Exams.update_exam_submission_content(submission, doc(answer))
    submission
  end

  # "flies" is the most frequent answer and "fly" the rarest, so a count-first
  # order would put them the other way round.
  setup do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)

    {:ok, exam} =
      Exams.create_exam(scope, %{
        name: "Vokabeln",
        content: doc(nil),
        sample_solution_points: %{"q-1" => 2}
      })

    {:ok, exam} = Exams.save_sample_solution_part(scope, exam, "q-1", doc("fly")["content"])
    {:ok, exam} = Exams.open_exam_session(:system, exam, "anonymous")
    {:ok, exam} = Exams.update_exam_status(:system, exam, "running")

    submit(exam, "anna", "fly")
    for name <- ~w(ben cleo dora), do: submit(exam, name, "flies")
    flew = for name <- ~w(emil fynn), do: submit(exam, name, "flew")
    submit(exam, "gina", nil)

    {:ok, _} = Exams.set_block_verdict_bulk(scope, exam, "q-1", 0, 1, Enum.map(flew, & &1.id))

    %{teacher: teacher, exam: exam}
  end

  defp open(conn, teacher, exam) do
    conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/correction/bulk/q-1")
  end

  defp card_order(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[data-bulk-power-row]")
    |> LazyHTML.attribute("data-group-text")
  end

  test "answers are listed full points, partial, zero, then no answer", %{conn: conn} = ctx do
    {:ok, view, _html} = open(conn, ctx.teacher, ctx.exam)

    assert card_order(view) == ["fly", "flew", "flies", ""]
  end

  test "judging a card keeps it in place until the question is reopened", %{conn: conn} = ctx do
    {:ok, view, _html} = open(conn, ctx.teacher, ctx.exam)

    render_click(view, "set_group_verdict", %{
      "index" => "0",
      "text" => "flies",
      "verdict" => "correct"
    })

    assert card_order(view) == ["fly", "flew", "flies", ""]

    {:ok, reopened, _html} = open(conn, ctx.teacher, ctx.exam)
    assert card_order(reopened) == ["flies", "fly", "flew", ""]
  end
end
