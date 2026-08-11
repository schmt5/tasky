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

    test "speichert den Freigabe-Modus", %{conn: conn, task: task} do
      {:ok, lv, _html} = live(conn, ~p"/tasks/#{task}/content?tab=musterloesung")

      lv
      |> element("form[phx-change='set_release_mode']")
      |> render_change(%{"mode" => "on_complete"})

      assert Tasky.Repo.reload!(task).solution_release_mode == "on_complete"
    end

    test "weist einen unbekannten Modus ab", %{conn: conn, task: task} do
      {:ok, lv, _html} = live(conn, ~p"/tasks/#{task}/content?tab=musterloesung")

      html =
        lv
        |> element("form[phx-change='set_release_mode']")
        |> render_change(%{"mode" => "irgendwas"})

      assert html =~ "Freigabe-Modus konnte nicht gespeichert werden"
      assert Tasky.Repo.reload!(task).solution_release_mode == "never"
    end
  end
end
