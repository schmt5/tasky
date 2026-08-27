defmodule TaskyWeb.TaskLive.FilesTest do
  @moduledoc """
  Die Datei-Abgaben-Übersicht einer Lerneinheit: eine Zeile pro Lernende/r,
  eine Spalte pro Upload-Feld.

  Wichtig sind die beiden Ränder: eine fehlende Abgabe muss als solche sichtbar
  bleiben (sonst sieht eine leere Zelle wie ein Anzeigefehler aus), und die
  Seite darf keiner fremden Lehrperson Dateien zeigen.
  """
  use TaskyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.TasksFixtures

  alias Tasky.Accounts.Scope
  alias Tasky.Courses
  alias Tasky.Tasks
  alias Tasky.Uploads

  setup %{conn: conn} do
    dir = Path.join(System.tmp_dir!(), "tasky_files_live_#{System.unique_integer([:positive])}")
    prev = Application.get_env(:tasky, :uploads_dir)
    Application.put_env(:tasky, :uploads_dir, dir)

    on_exit(fn ->
      File.rm_rf(dir)
      if prev, do: Application.put_env(:tasky, :uploads_dir, prev)
    end)

    teacher = user_fixture(%{role: "teacher"})
    teacher_scope = Scope.for_user(teacher)

    mia = user_fixture(%{role: "student", firstname: "Mia", lastname: "Muster"})
    ben = user_fixture(%{role: "student", firstname: "Ben", lastname: "Beispiel"})

    {:ok, course} = Courses.create_course(teacher_scope, %{name: "Testkurs"})
    task = task_fixture(teacher_scope, %{name: "Testaufgabe", course_id: course.id})
    {:ok, _} = Courses.enroll_student(course.id, mia.id)
    {:ok, _} = Courses.enroll_student(course.id, ben.id)

    {:ok, field} =
      Tasks.create_task_upload_field(teacher_scope, task, %{
        "label" => "Skizze",
        "allowed_types" => ["image", "pdf"],
        "required" => true
      })

    %{
      conn: log_in_user(conn, teacher),
      teacher_scope: teacher_scope,
      task: task,
      field: field,
      mia: mia,
      ben: ben
    }
  end

  defp upload(task, field, student, filename) do
    {:ok, submission} = Tasks.get_or_create_submission(Scope.for_user(student), task.id)

    src = Path.join(System.tmp_dir!(), "src_#{System.unique_integer([:positive])}")
    File.write!(src, "bytes")

    {:ok, meta} =
      Uploads.save_task_submission_file(
        task.id,
        submission.id,
        src,
        filename,
        field.allowed_types
      )

    {:ok, file} =
      Tasks.put_submission_file(submission, field, Map.put(meta, :original_name, filename))

    {submission, file}
  end

  test "lists every enrolled student, with and without a submitted file", %{
    conn: conn,
    task: task,
    field: field,
    mia: mia
  } do
    upload(task, field, mia, "skizze.png")

    {:ok, _lv, html} = live(conn, ~p"/progress/#{task.id}/files")

    assert html =~ "Mia Muster"
    assert html =~ "Ben Beispiel"
    assert html =~ "skizze.png"
    assert html =~ "Skizze"
    assert html =~ "Nicht hochgeladen"
  end

  test "offers a download link for a submitted file", %{
    conn: conn,
    task: task,
    field: field,
    mia: mia
  } do
    {submission, file} = upload(task, field, mia, "skizze.png")

    {:ok, lv, _html} = live(conn, ~p"/progress/#{task.id}/files")

    assert has_element?(
             lv,
             ~s{a[href="/tasks/#{task.id}/submissions/#{submission.id}/files/#{file.id}"]}
           )
  end

  test "opens an image in the preview modal and closes it again", %{
    conn: conn,
    task: task,
    field: field,
    mia: mia
  } do
    {submission, file} = upload(task, field, mia, "skizze.png")

    {:ok, lv, _html} = live(conn, ~p"/progress/#{task.id}/files")

    refute has_element?(lv, "#file-preview-modal")

    html =
      lv
      |> element(~s{button[phx-click="preview_file"][phx-value-file-id="#{file.id}"]})
      |> render_click()

    assert html =~ "file-preview-modal"

    assert html =~
             "/tasks/#{task.id}/submissions/#{submission.id}/files/#{file.id}/inline"

    refute lv |> render_click("close_preview", %{}) =~ "file-preview-modal"
  end

  test "gives a PDF an open-in-tab link but no preview button", %{
    conn: conn,
    task: task,
    field: field,
    mia: mia
  } do
    {submission, file} = upload(task, field, mia, "bericht.pdf")

    {:ok, lv, _html} = live(conn, ~p"/progress/#{task.id}/files")

    assert has_element?(
             lv,
             ~s{a[href="/tasks/#{task.id}/submissions/#{submission.id}/files/#{file.id}/inline"]}
           )

    refute has_element?(lv, ~s{button[phx-click="preview_file"]})
  end

  test "a non-image file id cannot be pushed into the preview modal", %{
    conn: conn,
    task: task,
    field: field,
    mia: mia
  } do
    {_submission, file} = upload(task, field, mia, "bericht.pdf")

    {:ok, lv, _html} = live(conn, ~p"/progress/#{task.id}/files")

    refute render_click(lv, "preview_file", %{"file-id" => to_string(file.id)}) =~
             "file-preview-modal"
  end

  test "explains itself when the unit has no upload fields", %{
    conn: conn,
    teacher_scope: teacher_scope,
    task: task,
    field: field
  } do
    {:ok, _} = Tasks.delete_task_upload_field(teacher_scope, field)

    {:ok, _lv, html} = live(conn, ~p"/progress/#{task.id}/files")

    assert html =~ "Keine Datei-Abgaben eingerichtet"
    assert html =~ "/tasks/#{task.id}/content?tab=dateien"
  end

  test "another teacher cannot reach the page", %{task: task} do
    other = user_fixture(%{role: "teacher"})
    conn = log_in_user(build_conn(), other)

    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/progress/#{task.id}/files") end
  end

  test "the progress page links here only when upload fields exist", %{
    conn: conn,
    teacher_scope: teacher_scope,
    task: task,
    field: field
  } do
    {:ok, lv, _html} = live(conn, ~p"/progress/#{task.id}")
    assert has_element?(lv, ~s{a[href="/progress/#{task.id}/files"]})

    {:ok, _} = Tasks.delete_task_upload_field(teacher_scope, field)

    {:ok, lv, _html} = live(conn, ~p"/progress/#{task.id}")
    refute has_element?(lv, ~s{a[href="/progress/#{task.id}/files"]})
  end
end
