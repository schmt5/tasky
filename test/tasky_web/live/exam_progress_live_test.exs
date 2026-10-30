defmodule TaskyWeb.ExamProgressLiveTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams

  defp text(t), do: %{"type" => "text", "text" => t}
  defp para(content), do: %{"type" => "paragraph", "content" => content}

  defp radio(oid, checked),
    do: %{
      "type" => "choice",
      "attrs" => %{"groupId" => "g1", "optionId" => oid, "checked" => checked}
    }

  # q-1 a radio group (always auto-corrected), q-2 a free text.
  defp doc(city \\ nil, reason \\ nil) do
    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "heading",
          "attrs" => %{"level" => 3, "partId" => "q-1"},
          "content" => [text("Hauptstadt")]
        },
        para([radio("g1-bern", city == :bern), text(" Bern")]),
        para([radio("g1-zh", city == :zh), text(" Zürich")]),
        %{
          "type" => "heading",
          "attrs" => %{"level" => 3, "partId" => "q-2"},
          "content" => [text("Begründung")]
        },
        %{
          "type" => "answerBlock",
          "attrs" => %{"answerId" => "t1"},
          "content" => [para(if(reason, do: [text(reason)], else: []))]
        }
      ]
    }
  end

  defp setup_exam(status \\ "running") do
    teacher = user_fixture(%{role: "teacher"})
    exam = exam_fixture(scope: user_scope_fixture(teacher), status: status)

    {:ok, exam} =
      exam
      |> Ecto.Changeset.change(%{content: doc(), sample_solution: %{"g1" => "g1-bern"}})
      |> Tasky.Repo.update()

    %{teacher: teacher, exam: exam}
  end

  defp open_progress(conn, teacher, exam),
    do: conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/cockpit/progress")

  defp cell(submission, part_id, status),
    do: "#cell-#{submission.id}-#{part_id}[data-status='#{status}']"

  test "shows one row per task and one column per participant", %{conn: conn} do
    %{teacher: teacher, exam: exam} = setup_exam()
    anna = exam_submission_fixture(exam, %{"firstname" => "Anna", "email" => "anna@example.com"})
    ben = exam_submission_fixture(exam, %{"firstname" => "Ben", "email" => "ben@example.com"})

    {:ok, view, _html} = open_progress(conn, teacher, exam)

    assert has_element?(view, "#exam-progress-grid")
    assert has_element?(view, "#part-q-1")
    assert has_element?(view, "#part-q-2")
    assert has_element?(view, "#participant-#{anna.id}")
    assert has_element?(view, "#participant-#{ben.id}")
    assert has_element?(view, cell(anna, "q-1", :not_started))
  end

  test "picks up saved answers on the next tick", %{conn: conn} do
    %{teacher: teacher, exam: exam} = setup_exam()
    anna = exam_submission_fixture(exam, %{"firstname" => "Anna", "email" => "anna@example.com"})
    ben = exam_submission_fixture(exam, %{"firstname" => "Ben", "email" => "ben@example.com"})

    {:ok, view, _html} = open_progress(conn, teacher, exam)

    {:ok, _} = Exams.update_exam_submission_content(anna, doc(:bern, "Weil"))
    {:ok, _} = Exams.update_exam_submission_content(ben, doc(:zh))
    send(view.pid, :tick)

    assert has_element?(view, cell(anna, "q-1", :correct))
    assert has_element?(view, cell(anna, "q-2", :answered))
    assert has_element?(view, cell(ben, "q-1", :wrong))
    assert has_element?(view, cell(ben, "q-2", :not_started))
  end

  test "a participant joining later gets a column, a hand-in a badge", %{conn: conn} do
    %{teacher: teacher, exam: exam} = setup_exam()
    anna = exam_submission_fixture(exam, %{"firstname" => "Anna", "email" => "anna@example.com"})
    {:ok, view, _html} = open_progress(conn, teacher, exam)

    ben = exam_submission_fixture(exam, %{"firstname" => "Ben", "email" => "ben@example.com"})
    send(view.pid, :tick)
    assert has_element?(view, "#participant-#{ben.id}")

    refute has_element?(view, "#submitted-#{anna.id}")
    {:ok, _} = Exams.submit_exam_submission(anna)
    assert has_element?(view, "#submitted-#{anna.id}")
  end

  test "hides the names", %{conn: conn} do
    %{teacher: teacher, exam: exam} = setup_exam()
    anna = exam_submission_fixture(exam, %{"firstname" => "Anna", "email" => "anna@example.com"})
    {:ok, view, _html} = open_progress(conn, teacher, exam)

    assert has_element?(view, "#participant-link-#{anna.id}[data-tip='Anna Muster']")
    view |> element("#toggle-anonymize") |> render_click()
    assert has_element?(view, "#participant-link-#{anna.id}[data-tip='Lernende 1']")
  end

  test "shows an empty state without participants", %{conn: conn} do
    %{teacher: teacher, exam: exam} = setup_exam()
    {:ok, view, _html} = open_progress(conn, teacher, exam)

    assert has_element?(view, "#progress-empty")
    refute has_element?(view, "#exam-progress-grid")
  end

  test "is not open to another teacher", %{conn: conn} do
    %{exam: exam} = setup_exam()
    other = user_fixture(%{role: "teacher"})

    assert_raise Ecto.NoResultsError, fn -> open_progress(conn, other, exam) end
  end

  test "the cockpit links to it", %{conn: conn} do
    %{teacher: teacher, exam: exam} = setup_exam()
    {:ok, view, _html} = conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/cockpit")

    assert has_element?(view, "#progress-card[href='/exams/#{exam.id}/cockpit/progress']")
  end
end
