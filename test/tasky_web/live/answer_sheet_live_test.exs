defmodule TaskyWeb.AnswerSheetLiveTest do
  use TaskyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures
  import Tasky.TasksFixtures

  alias Tasky.Accounts.Scope
  alias Tasky.Courses
  alias Tasky.Exams
  alias Tasky.Tasks

  defp skeleton(question \\ "Frage 1") do
    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "heading",
          "attrs" => %{"level" => 3, "partId" => "q-1"},
          "content" => [%{"type" => "text", "text" => question}]
        },
        %{
          "type" => "paragraph",
          "content" => [
            %{"type" => "text", "text" => "Die Hauptstadt ist "},
            %{"type" => "lueckentext", "attrs" => %{"answerId" => "gap"}}
          ]
        },
        %{
          "type" => "answerBlock",
          "attrs" => %{"answerId" => "block"},
          "content" => [%{"type" => "paragraph"}]
        }
      ]
    }
  end

  defp answer_text(content, id) do
    {_skeleton, answers} = Tasky.Correction.AnswerKey.split(content)
    Tasky.Correction.PlainAnswers.block_text(answers[id] || [])
  end

  defp gap_text(content, id) do
    {_skeleton, answers} = Tasky.Correction.AnswerKey.split(content)
    Tasky.Correction.PlainAnswers.gap_text(answers[id] || [])
  end

  defp put_json(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put(path, body)
  end

  describe "guest exam" do
    setup do
      exam = exam_fixture(status: "running", attrs: %{content: skeleton()})
      %{exam: exam, submission: exam_submission_fixture(exam)}
    end

    test "renders one native field per answer", %{conn: conn, submission: submission} do
      {:ok, view, _html} = live(conn, ~p"/guest/exam/#{submission.exam_token}")

      sheet = "#exam-answers-#{submission.id}"
      assert has_element?(view, "#{sheet} input.exam-doc__gap[data-answer-id=gap]")
      assert has_element?(view, "#{sheet} textarea[data-answer-id=block]")
      assert has_element?(view, "#{sheet}[data-save-url]")
    end

    test "the save endpoint takes the field values", %{conn: conn, submission: submission} do
      conn =
        put_json(conn, ~p"/api/guest/exam/#{submission.exam_token}/content", %{
          "answers" => %{"gap" => "Bern", "block" => "Zeile 1\nZeile 2"},
          "choices" => %{}
        })

      assert %{"ok" => true} = json_response(conn, 200)

      content = Tasky.Repo.get!(Tasky.Exams.ExamSubmission, submission.id).content
      assert answer_text(content, "block") == "Zeile 1\nZeile 2"
      assert gap_text(content, "gap") == "Bern"
    end

    test "refuses an answer over the limit", %{conn: conn, submission: submission} do
      too_long = String.duplicate("x", Tasky.Correction.PlainAnswers.max_gap_chars() + 1)

      conn =
        put_json(conn, ~p"/api/guest/exam/#{submission.exam_token}/content", %{
          "answers" => %{"gap" => too_long}
        })

      assert json_response(conn, 422)
    end

    test "a whole-document save cannot rewrite the question", %{
      conn: conn,
      submission: submission
    } do
      tampered =
        skeleton("Die Antwort ist Bern")
        |> put_in(["content", Access.at(2), "content"], [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "meins"}]}
        ])

      conn =
        put_json(conn, ~p"/api/guest/exam/#{submission.exam_token}/content", %{
          "content" => tampered
        })

      assert json_response(conn, 200)

      content = Tasky.Repo.get!(Tasky.Exams.ExamSubmission, submission.id).content

      assert get_in(content, ["content", Access.at(0), "content", Access.at(0), "text"]) ==
               "Frage 1"

      assert answer_text(content, "block") == "meins"
    end
  end

  describe "learning unit" do
    setup %{conn: conn} do
      teacher = user_fixture(%{role: "teacher"})
      student = user_fixture(%{role: "student"})
      {:ok, course} = Courses.create_course(Scope.for_user(teacher), %{name: "Kurs"})
      {:ok, _} = Courses.enroll_student(course.id, student.id)

      task = task_fixture(teacher, %{name: "Einheit", course_id: course.id, status: "open"})
      {:ok, task} = Tasks.save_task_content(Scope.for_user(teacher), task, skeleton())

      %{conn: log_in_user(conn, student), student: student, task: task}
    end

    test "an editable unit gets the answer sheet with a save url", %{
      conn: conn,
      student: student,
      task: task
    } do
      {:ok, view, _html} = live(conn, ~p"/student/tasks/#{task.id}")
      submission = Tasks.get_submission_for_student(task.id, student.id)

      sheet = "#task-answers-#{submission.id}-edit"
      assert has_element?(view, "#{sheet}[data-save-url]")
      assert has_element?(view, "#{sheet} textarea[data-answer-id=block]:not([disabled])")
    end

    test "the save endpoint takes the field values, the read-back is locked", %{
      conn: conn,
      student: student,
      task: task
    } do
      {:ok, _view, _html} = live(conn, ~p"/student/tasks/#{task.id}")

      conn
      |> put_json(~p"/api/student/tasks/#{task.id}/answers", %{
        "answers" => %{"block" => "Meine Antwort"}
      })
      |> json_response(200)

      submission = Tasks.get_submission_for_student(task.id, student.id)
      assert answer_text(submission.content, "block") == "Meine Antwort"

      {:ok, _} = Tasks.complete_task(Scope.for_user(student), submission.id)

      {:ok, view, _html} = live(conn, ~p"/student/tasks/#{task.id}?preview=true")
      sheet = "#task-answers-#{submission.id}-read"
      refute has_element?(view, "#{sheet}[data-save-url]")
      assert has_element?(view, "#{sheet} textarea[data-answer-id=block][disabled]")
      assert view |> element("#{sheet} textarea") |> render() =~ "Meine Antwort"
    end
  end

  describe "teacher preview" do
    test "shows the exam as learners see it, without saving", %{conn: conn} do
      teacher = user_fixture(%{role: "teacher"})
      scope = user_scope_fixture(teacher)
      exam = exam_fixture(scope: scope, attrs: %{content: skeleton()})

      {:ok, view, _html} =
        conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/content?tab=vorschau")

      assert has_element?(view, "#exam-preview-#{exam.id}-0 textarea[data-answer-id=block]")
      refute has_element?(view, "#exam-preview-#{exam.id}-0[data-save-url]")
    end

    test "follows a save that lands after the switch to the preview", %{conn: conn} do
      teacher = user_fixture(%{role: "teacher"})
      scope = user_scope_fixture(teacher)
      exam = exam_fixture(scope: scope, attrs: %{content: skeleton()})

      {:ok, view, _html} =
        conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/content?tab=vorschau")

      {:ok, _exam} = Exams.save_exam_structure(scope, exam, skeleton("Neue Frage"))

      assert view |> element("#exam-preview-#{exam.id}-1") |> render() =~ "Neue Frage"
    end

    test "is not offered for a free-document exam", %{conn: conn} do
      teacher = user_fixture(%{role: "teacher"})
      exam = exam_fixture(scope: user_scope_fixture(teacher), answer_mode: "free_document")

      {:ok, view, _html} =
        conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/content?tab=vorschau")

      refute has_element?(view, "#exam-preview-#{exam.id}-0")
      assert has_element?(view, "#exam-content-editor-#{exam.id}")
    end

    test "shows the learning unit as learners see it", %{conn: conn} do
      teacher = user_fixture(%{role: "teacher"})
      {:ok, course} = Courses.create_course(Scope.for_user(teacher), %{name: "Kurs"})
      task = task_fixture(teacher, %{name: "Einheit", course_id: course.id})
      {:ok, task} = Tasks.save_task_content(Scope.for_user(teacher), task, skeleton())

      {:ok, view, _html} =
        conn |> log_in_user(teacher) |> live(~p"/tasks/#{task}/content?tab=vorschau")

      assert has_element?(view, "#task-preview-#{task.id}-0 input[data-answer-id=gap]")
    end
  end
end
