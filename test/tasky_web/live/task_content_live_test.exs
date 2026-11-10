defmodule TaskyWeb.TaskLive.ContentTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.CoursesFixtures
  import Tasky.TasksFixtures

  alias Tasky.Accounts.Scope
  alias Tasky.Tasks

  setup %{conn: conn} do
    teacher = user_fixture(%{role: "teacher"})
    scope = Scope.for_user(teacher)
    course = course_fixture(scope: scope)
    task = task_fixture(scope, %{name: "Testaufgabe", course_id: course.id})

    %{conn: log_in_user(conn, teacher), scope: scope, task: task}
  end

  defp question(part_id) do
    %{
      "type" => "heading",
      "attrs" => %{"level" => 3, "partId" => part_id},
      "content" => [%{"type" => "text", "text" => "Frage"}]
    }
  end

  # One question with one answer field, at position 1.
  defp doc_with_answer do
    %{
      "type" => "doc",
      "content" => [
        question("q-1"),
        %{
          "type" => "answerBlock",
          "attrs" => %{"answerId" => "a1"},
          "content" => [%{"type" => "paragraph"}]
        }
      ]
    }
  end

  describe "Musterlösung tab" do
    test "zeigt einen Leerzustand ohne Antwortfelder", %{conn: conn, task: task} do
      {:ok, _lv, html} = live(conn, ~p"/tasks/#{task}/content?tab=musterloesung")

      assert html =~ "Noch keine Frage vorhanden"
      refute html =~ "sample-solution-part-editor"
    end

    test "hängt den Editor mit dem antwortgefüllten Dokument ein", %{
      conn: conn,
      scope: scope,
      task: task
    } do
      {:ok, task} = Tasks.save_task_content(scope, task, doc_with_answer())

      filled =
        put_in(doc_with_answer(), ["content", Access.at(1), "content"], [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "LOESUNGSTEXT"}]}
        ])

      task = Tasky.TasksFixtures.sample_solution_fixture(task, filled)

      {:ok, lv, html} = live(conn, ~p"/tasks/#{task}/content?tab=musterloesung")

      assert has_element?(lv, "#sample-solution-part-editor-#{task.id}-q-1")
      assert html =~ "LOESUNGSTEXT"
      refute html =~ "Noch keine Frage vorhanden"
    end

    test "warnt vor Antwortfeldern ausserhalb einer Frage", %{
      conn: conn,
      scope: scope,
      task: task
    } do
      %{"content" => [_question, answer]} = doc_with_answer()
      loose = %{"type" => "doc", "content" => [answer]}
      {:ok, task} = Tasks.save_task_content(scope, task, loose)

      {:ok, lv, _html} = live(conn, ~p"/tasks/#{task}/content?tab=musterloesung")

      assert has_element?(lv, "#loose-answers-note")
      refute has_element?(lv, "[id^='sample-solution-part-editor-']")
    end

    test "speichert die Korrekturoptionen einer Frage", %{conn: conn, scope: scope, task: task} do
      {:ok, task} = Tasks.save_task_content(scope, task, doc_with_answer())

      {:ok, lv, _html} = live(conn, ~p"/tasks/#{task}/content?tab=musterloesung")

      # Neue Fragen einer Lerneinheit prüfen sich selbst, ohne Gross-/Kleinschreibung.
      assert lv |> element("#correction-options-summary-q-1") |> render() =~ "Auto-Korrektur"

      lv |> element("#correction-options-btn-q-1") |> render_click()
      assert has_element?(lv, "#correction-options-modal")
      refute has_element?(lv, "#correction-options-modal input[name='options[max_points]']")

      lv
      |> form("#correction-options-form-q-1", %{
        "options" => %{"ignore_case" => "false", "ignore_punctuation" => "true"}
      })
      |> render_submit()

      refute has_element?(lv, "#correction-options-modal")

      assert %{"auto_correct" => true, "ignore_case" => false, "ignore_punctuation" => true} =
               Tasks.get_task!(scope, task.id).correction_config["q-1"]
    end

    # Der Freigabe-Modus wird beim Erstellen/Bearbeiten der Lerneinheit gesetzt,
    # nicht hier.
    test "enthält keine Modus-Auswahl mehr", %{conn: conn, task: task} do
      {:ok, _lv, html} = live(conn, ~p"/tasks/#{task}/content?tab=musterloesung")

      refute html =~ "set_release_mode"
      refute html =~ "solution-release-mode"
    end
  end

  describe "Dateien tab" do
    test "beherbergt die Lösungsdateien unterhalb der Datei-Abgaben", %{
      conn: conn,
      scope: scope,
      task: task
    } do
      src = Path.join(System.tmp_dir!(), "sol_#{System.unique_integer([:positive])}")
      File.write!(src, "bytes")
      {:ok, meta} = Tasky.Uploads.save_task_solution_file(task.id, src, "loesung.docx")

      {:ok, _} =
        Tasks.create_task_solution_file(
          scope,
          task,
          Map.put(meta, :original_name, "loesung.docx")
        )

      {:ok, _lv, html} = live(conn, ~p"/tasks/#{task}/content?tab=dateien")

      assert html =~ "Lösungsdateien"
      assert html =~ "loesung.docx"
      assert html =~ "solution-file-upload-form"

      # Reihenfolge: Anhänge, Datei-Abgaben, dann Lösungsdateien.
      assert :binary.match(html, "Datei-Abgaben") < :binary.match(html, "Lösungsdateien")
    end

    test "die Lösungsdateien stehen nicht mehr im Musterlösungs-Tab", %{conn: conn, task: task} do
      {:ok, _lv, html} = live(conn, ~p"/tasks/#{task}/content?tab=musterloesung")

      refute html =~ "solution-file-upload-form"
      refute html =~ "Lösungsdateien"
    end
  end

  describe "malformed ids from the client" do
    test "leave the view running", %{conn: conn, task: task} do
      {:ok, view, _html} = live(conn, ~p"/tasks/#{task}/content?tab=dateien")

      for event <-
            ~w(delete_solution_file delete_attachment edit_upload_field delete_upload_field),
          id <- ["abc", "", "1.5"] do
        render_hook(view, event, %{"id" => id})
      end

      assert Process.alive?(view.pid)
    end
  end
end
