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
    test "offers both modes", %{conn: conn} do
      {conn, _scope} = teacher_conn(conn)
      {:ok, view, html} = live(conn, ~p"/exams/new")

      assert has_element?(view, "#exam-form")
      assert has_element?(view, "#exam_answer_mode-answer_fields")
      assert has_element?(view, "#exam_answer_mode-free_document")
      assert html =~ "Antwortfelder"
      assert html =~ "Freies Dokument"
    end

    test "the panel explains the mode that is currently selected", %{conn: conn} do
      {conn, _scope} = teacher_conn(conn)
      {:ok, view, html} = live(conn, ~p"/exams/new")

      assert html =~ "Musterlösung pro Antwortfeld möglich"
      refute html =~ "Bewertet wird das Dokument als Ganzes"

      # Der Picker braucht kein eigenes Event: `phx-change` baut den Changeset
      # neu, und `@field.value` trägt die Auswahl zurück ins Panel.
      changed =
        view
        |> form("#exam-form", exam: %{answer_mode: "free_document"})
        |> render_change()

      assert changed =~ "Bewertet wird das Dokument als Ganzes"
      refute changed =~ "Musterlösung pro Antwortfeld möglich"
    end

    test "creating with free_document persists the mode", %{conn: conn} do
      {conn, scope} = teacher_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/exams/new")

      {:ok, _view, _html} =
        view
        |> form("#exam-form", exam: %{name: "Mein Aufsatz", answer_mode: "free_document"})
        |> render_submit()
        |> follow_redirect(conn)

      assert [exam] = Exams.list_exams(scope)
      assert exam.answer_mode == "free_document"
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

      {:ok, view, _html} = live(conn, ~p"/exams/#{exam}/edit")

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

  describe "learner's editor" do
    test "a free-document exam mounts the freeDocument preset", %{conn: conn} do
      exam = exam_fixture(answer_mode: "free_document", status: "running")
      submission = exam_submission_fixture(exam)

      {:ok, _view, html} = live(conn, ~p"/guest/exam/#{submission.exam_token}")

      assert html =~ ~s(data-editor-mode="freeDocument")
    end

    test "an answer-field exam still mounts the student preset", %{conn: conn} do
      exam = exam_fixture(status: "running")
      submission = exam_submission_fixture(exam)

      {:ok, _view, html} = live(conn, ~p"/guest/exam/#{submission.exam_token}")

      assert html =~ ~s(data-editor-mode="student")
    end
  end
end
