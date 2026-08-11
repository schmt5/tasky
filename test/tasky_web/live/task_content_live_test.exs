defmodule TaskyWeb.TaskLive.ContentTest do
  use TaskyWeb.ConnCase, async: false

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

  defp doc_with_answer do
    %{
      "type" => "doc",
      "content" => [
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

      assert html =~ "Noch keine Antwortfelder"
      refute html =~ "task-sample-solution-editor"
    end

    test "hängt den Editor mit dem antwortgefüllten Dokument ein", %{
      conn: conn,
      scope: scope,
      task: task
    } do
      {:ok, task} = Tasks.save_task_content(scope, task, doc_with_answer())

      filled =
        put_in(doc_with_answer(), ["content", Access.at(0), "content"], [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "LOESUNGSTEXT"}]}
        ])

      {:ok, task} = Tasks.save_sample_solution(scope, task, filled)

      {:ok, _lv, html} = live(conn, ~p"/tasks/#{task}/content?tab=musterloesung")

      assert html =~ "task-sample-solution-editor-#{task.id}"
      assert html =~ "LOESUNGSTEXT"
      refute html =~ "Noch keine Antwortfelder"
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
      dir =
        Path.join(System.tmp_dir!(), "tasky_uploads_test_#{System.unique_integer([:positive])}")

      prev = Application.get_env(:tasky, :uploads_dir)
      Application.put_env(:tasky, :uploads_dir, dir)

      on_exit(fn ->
        File.rm_rf(dir)
        if prev, do: Application.put_env(:tasky, :uploads_dir, prev)
      end)

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
end
