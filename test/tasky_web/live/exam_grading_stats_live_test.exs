defmodule TaskyWeb.ExamGradingStatsLiveTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams

  # The fixture exam has no sample solution points, so there is no calculated
  # mark — every figure in the card comes from the marks set here.
  defp graded_exam(marks) do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)
    exam = exam_fixture(scope: scope, status: "running")
    {:ok, exam, _} = Exams.set_mark_step(scope, exam, "0.1")

    submissions =
      for {mark, i} <- Enum.with_index(marks) do
        submission =
          exam_submission_fixture(exam, %{
            "firstname" => "Person#{i}",
            "lastname" => "Muster",
            "email" => "person#{i}@example.com"
          })

        if mark do
          {:ok, submission} = Exams.set_submission_mark(scope, submission, mark)
          submission
        else
          submission
        end
      end

    {:ok, exam} = Exams.update_exam_status(scope, exam, "finished")

    %{teacher: teacher, exam: exam, submissions: submissions}
  end

  defp open(conn, teacher, exam) do
    conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/correction/grading")
  end

  defp bucket_count(view, idx) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#mark-bucket-#{idx}")
    |> LazyHTML.attribute("data-count")
    |> List.first()
  end

  defp text_of(view, selector) do
    view |> element(selector) |> render() |> LazyHTML.from_fragment() |> LazyHTML.text()
  end

  test "the card shows average, pass count and the distribution", %{conn: conn} do
    %{teacher: teacher, exam: exam} = graded_exam([4.0, 5.0, 3.5, nil])

    {:ok, view, _html} = open(conn, teacher, exam)

    assert has_element?(view, "#grading-stats")
    assert has_element?(view, "#mark-histogram")
    assert text_of(view, "#grading-stats-average") =~ "4.17"
    assert text_of(view, "#grading-stats-passed") =~ "2/3"

    # 3.5 → «3.5–3.9», 4.0 → «4–4.4» only, 5.0 → «5–5.4».
    assert bucket_count(view, 5) == "1"
    assert bucket_count(view, 6) == "1"
    assert bucket_count(view, 7) == "0"
    assert bucket_count(view, 8) == "1"
  end

  test "changing a mark updates the card", %{conn: conn} do
    %{teacher: teacher, exam: exam, submissions: [first | _]} = graded_exam([4.0, 5.0])

    {:ok, view, _html} = open(conn, teacher, exam)
    assert bucket_count(view, 6) == "1"

    render_click(view, "set_mark", %{"submission_id" => to_string(first.id), "mark" => "6"})

    assert text_of(view, "#grading-stats-average") =~ "5.5"
    assert bucket_count(view, 6) == "0"
    assert bucket_count(view, 9) == "1"
  end

  test "without participants there is no card", %{conn: conn} do
    %{teacher: teacher, exam: exam} = graded_exam([])

    {:ok, view, _html} = open(conn, teacher, exam)

    refute has_element?(view, "#grading-stats")
  end
end
