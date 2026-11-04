defmodule TaskyWeb.ExamAnswerModeLiveTest do
  @moduledoc """
  The exam mode across the surfaces that have to react to it: the create form
  where it is chosen, the authoring page, and the learner's editor island.

  The mode reaches the React editor as `data-editor-mode`, so these assertions
  are the seam between the Elixir and the JS half of the feature.
  """

  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams

  defp teacher_conn(conn) do
    teacher = user_fixture(%{role: "teacher"})
    {log_in_user(conn, teacher), user_scope_fixture(teacher)}
  end

  describe "create form" do
    test "offers answer fields and an essay, no longer the free document", %{conn: conn} do
      {conn, _scope} = teacher_conn(conn)
      {:ok, view, html} = live(conn, ~p"/exams/new")

      assert has_element?(view, "#exam-form")
      assert has_element?(view, "#exam_answer_mode-answer_fields")
      assert has_element?(view, "#exam_answer_mode-essay")
      refute has_element?(view, "#exam_answer_mode-free_document")
      assert html =~ "Antwortfelder"
      assert html =~ "Aufsatz"
    end

    test "the panel explains the kind that is currently selected", %{conn: conn} do
      {conn, _scope} = teacher_conn(conn)
      {:ok, view, html} = live(conn, ~p"/exams/new")

      assert html =~ "Musterlösung pro Antwortfeld möglich"
      refute html =~ "Erwartungshorizont als Musterlösung möglich"

      changed =
        view
        |> form("#exam-form", exam: %{answer_mode: "essay"})
        |> render_change()

      assert changed =~ "Erwartungshorizont als Musterlösung möglich"
      refute changed =~ "Musterlösung pro Antwortfeld möglich"
      assert has_element?(view, "#exam_answer_mode-essay[checked]")
    end

    test "an essay is an answer-field exam that starts with an essay field", %{conn: conn} do
      {conn, scope} = teacher_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/exams/new")

      {:ok, _view, _html} =
        view
        |> form("#exam-form", exam: %{name: "Mein Aufsatz", answer_mode: "essay"})
        |> render_submit()
        |> follow_redirect(conn)

      assert [exam] = Exams.list_exams(scope)
      exam = Exams.get_exam!(scope, exam.id)
      assert exam.answer_mode == "answer_fields"

      assert [%{"type" => "heading"}, _task, %{"type" => "answerBlock", "attrs" => attrs}, _] =
               exam.content["content"]

      assert attrs["rich"] == true
      assert attrs["answerId"]
    end

    test "defaults to answer_fields when the radio is left alone", %{conn: conn} do
      {conn, scope} = teacher_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/exams/new")

      {:ok, _view, _html} =
        view
        |> form("#exam-form", exam: %{name: "Klassische Prüfung"})
        |> render_submit()
        |> follow_redirect(conn)

      assert [exam] = Exams.list_exams(scope)
      assert exam.answer_mode == "answer_fields"
    end

    test "the rename form does not offer the mode", %{conn: conn} do
      {conn, scope} = teacher_conn(conn)
      exam = exam_fixture(scope: scope, answer_mode: "free_document")

      {:ok, view, _html} = live(conn, ~p"/exams/#{exam}")
      view |> element("#rename-exam") |> render_click()

      assert has_element?(view, "#rename-exam-form-#{exam.id}")
      refute has_element?(view, "#exam_answer_mode-answer_fields")
    end
  end

  describe "authoring page" do
    test "a free-document exam gets the freeDocument editor and a points tab", %{conn: conn} do
      {conn, scope} = teacher_conn(conn)
      exam = exam_fixture(scope: scope, answer_mode: "free_document")

      {:ok, _view, html} = live(conn, ~p"/exams/#{exam}/content?tab=inhalt")
      assert html =~ ~s(data-editor-mode="freeDocument")

      {:ok, _view, html} = live(conn, ~p"/exams/#{exam}/content?tab=musterloesung")
      assert html =~ "Max. Punkte"
      # no sample-solution editors and no shared toolbar to bind them to
      refute html =~ "sample-solution-part-editor-"
      refute html =~ ~s(id="solution-toolbar-#{exam.id}")
    end

    test "an answer-field exam is unchanged", %{conn: conn} do
      {conn, scope} = teacher_conn(conn)
      exam = exam_fixture(scope: scope)

      {:ok, _view, html} = live(conn, ~p"/exams/#{exam}/content?tab=inhalt")
      assert html =~ ~s(data-editor-mode="author")
    end
  end

  describe "learner's surface" do
    test "a free-document exam mounts the editor", %{conn: conn} do
      exam = exam_fixture(answer_mode: "free_document", status: "running")
      submission = exam_submission_fixture(exam)

      {:ok, view, _html} = live(conn, ~p"/guest/exam/#{submission.exam_token}")

      assert has_element?(view, "#exam-submission-editor-#{submission.id}")
      refute has_element?(view, "#exam-answers-#{submission.id}")
    end

    test "an answer-field exam gets the native answer sheet", %{conn: conn} do
      exam = exam_fixture(status: "running")
      submission = exam_submission_fixture(exam)

      {:ok, view, _html} = live(conn, ~p"/guest/exam/#{submission.exam_token}")

      assert has_element?(view, "#exam-answers-#{submission.id}[phx-hook=ExamAnswersForm]")
      refute has_element?(view, "#exam-submission-editor-#{submission.id}")
    end
  end
end
