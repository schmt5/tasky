defmodule TaskyWeb.Student.TaskLiveTest do
  use TaskyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.TasksFixtures

  alias Tasky.Accounts.Scope
  alias Tasky.Courses

  setup %{conn: conn} do
    teacher = user_fixture(%{role: "teacher"})
    student = user_fixture(%{role: "student"})
    {:ok, course} = Courses.create_course(Scope.for_user(teacher), %{name: "Testkurs"})
    # Published on purpose: the student surface only ever shows published units,
    # and the fixture default is "draft".
    task =
      task_fixture(teacher, %{
        name: "Testaufgabe",
        course_id: course.id,
        status: "published"
      })

    %{conn: log_in_user(conn, student), student: student, course: course, task: task}
  end

  test "enrolled student cannot open a draft unit of their course", %{
    conn: conn,
    student: student,
    course: course,
    task: task
  } do
    {:ok, _} = Courses.enroll_student(course.id, student.id)
    {:ok, draft} = Tasky.Tasks.update_task(teacher_scope(task), task, %{status: "draft"})

    assert {:error, {:live_redirect, %{to: "/student/courses"}}} =
             live(conn, ~p"/student/tasks/#{draft.id}")

    refute Tasky.Tasks.get_submission_for_student(draft.id, student.id)
  end

  test "enrolled student cannot open an archived unit of their course", %{
    conn: conn,
    student: student,
    course: course,
    task: task
  } do
    {:ok, _} = Courses.enroll_student(course.id, student.id)
    {:ok, archived} = Tasky.Tasks.update_task(teacher_scope(task), task, %{status: "archived"})

    assert {:error, {:live_redirect, %{to: "/student/courses"}}} =
             live(conn, ~p"/student/tasks/#{archived.id}")
  end

  defp teacher_scope(task),
    do: Scope.for_user(Tasky.Repo.get!(Tasky.Accounts.User, task.user_id))

  test "enrolled student can open the task", %{
    conn: conn,
    student: student,
    course: course,
    task: task
  } do
    {:ok, _} = Courses.enroll_student(course.id, student.id)

    {:ok, _lv, html} = live(conn, ~p"/student/tasks/#{task.id}")
    assert html =~ "Testaufgabe"
  end

  test "student not enrolled in the course is redirected and no submission is created", %{
    conn: conn,
    student: student,
    task: task
  } do
    assert {:error, {:live_redirect, %{to: "/student/courses"}}} =
             live(conn, ~p"/student/tasks/#{task.id}")

    refute Tasky.Tasks.get_submission_for_student(task.id, student.id)
  end

  test "malformed task id redirects instead of crashing", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/student/courses"}}} =
             live(conn, "/student/tasks/not-a-number")
  end

  describe "Musterlösung" do
    setup %{student: student, course: course, task: task} do
      {:ok, _} = Courses.enroll_student(course.id, student.id)

      teacher_scope = Scope.for_user(Tasky.Repo.get!(Tasky.Accounts.User, task.user_id))

      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "answerBlock",
            "attrs" => %{"answerId" => "a1"},
            "content" => [%{"type" => "paragraph"}]
          }
        ]
      }

      {:ok, task} = Tasky.Tasks.save_task_content(teacher_scope, task, doc)

      filled =
        put_in(doc, ["content", Access.at(0), "content"], [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "MUSTERLOESUNG"}]}
        ])

      {:ok, task} = Tasky.Tasks.save_sample_solution(teacher_scope, task, filled)

      %{task: task, teacher_scope: teacher_scope}
    end

    test "bleibt im Modus never unsichtbar", %{conn: conn, task: task} do
      {:ok, _lv, html} = live(conn, ~p"/student/tasks/#{task.id}")

      refute html =~ "MUSTERLOESUNG"
      refute html =~ "task-solution-viewer"
    end

    test "erscheint nach manueller Freigabe", %{
      conn: conn,
      task: task,
      teacher_scope: teacher_scope,
      student: student
    } do
      {:ok, task} =
        Tasky.Tasks.update_task(teacher_scope, task, %{solution_release_mode: "manual"})

      {:ok, _lv, html} = live(conn, ~p"/student/tasks/#{task.id}")
      refute html =~ "MUSTERLOESUNG"

      submission = Tasky.Tasks.get_submission_for_student(task.id, student.id)
      {:ok, _} = Tasky.Tasks.release_solution(teacher_scope, task, submission.id)

      {:ok, _lv, html} = live(conn, ~p"/student/tasks/#{task.id}")
      assert html =~ "MUSTERLOESUNG"
      assert html =~ "task-solution-viewer"
    end

    test "erscheint im Modus on_complete, sobald erledigt", %{
      conn: conn,
      task: task,
      teacher_scope: teacher_scope,
      student: student
    } do
      {:ok, task} =
        Tasky.Tasks.update_task(teacher_scope, task, %{solution_release_mode: "on_complete"})

      {:ok, _lv, html} = live(conn, ~p"/student/tasks/#{task.id}")
      refute html =~ "MUSTERLOESUNG"

      submission = Tasky.Tasks.get_submission_for_student(task.id, student.id)
      {:ok, _} = Tasky.Tasks.complete_task(Scope.for_user(student), submission.id)

      {:ok, _lv, html} = live(conn, ~p"/student/tasks/#{task.id}?preview=true&tab=musterloesung")
      assert html =~ "MUSTERLOESUNG"
    end

    test "zeigt Lösungsdateien erst nach der Freigabe", %{
      conn: conn,
      task: task,
      teacher_scope: teacher_scope,
      student: student
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
        Tasky.Tasks.create_task_solution_file(
          teacher_scope,
          task,
          Map.put(meta, :original_name, "loesung.docx")
        )

      {:ok, task} =
        Tasky.Tasks.update_task(teacher_scope, task, %{solution_release_mode: "manual"})

      {:ok, _lv, html} = live(conn, ~p"/student/tasks/#{task.id}")
      refute html =~ "loesung.docx"

      submission = Tasky.Tasks.get_submission_for_student(task.id, student.id)
      {:ok, _} = Tasky.Tasks.release_solution(teacher_scope, task, submission.id)

      {:ok, _lv, html} = live(conn, ~p"/student/tasks/#{task.id}")
      assert html =~ "loesung.docx"
      assert html =~ "Lösungsdateien"
    end

    test "zeigt die Korrektur erst nach der Freigabe und ersetzt die Rücklese-Ansicht", %{
      conn: conn,
      task: task,
      teacher_scope: teacher_scope,
      student: student
    } do
      {:ok, task} =
        Tasky.Tasks.update_task(teacher_scope, task, %{solution_release_mode: "manual"})

      {:ok, submission} =
        Tasky.Tasks.get_or_create_submission(Scope.for_user(student), task.id)

      {:ok, submission} = Tasky.Tasks.complete_task(Scope.for_user(student), submission.id)

      corrected = %{
        "type" => "doc",
        "content" => [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "ANMERKUNG-LP"}]}
        ]
      }

      {:ok, _} =
        Tasky.Tasks.save_correction_content(teacher_scope, task, submission.id, corrected)

      {:ok, _lv, html} = live(conn, ~p"/student/tasks/#{task.id}?preview=true")
      refute html =~ "ANMERKUNG-LP"
      assert html =~ "task-answers-editor-#{submission.id}"

      {:ok, _} = Tasky.Tasks.release_solution(teacher_scope, task, submission.id)

      {:ok, _lv, html} = live(conn, ~p"/student/tasks/#{task.id}?preview=true")
      assert html =~ "ANMERKUNG-LP"
      assert html =~ "Mit den Anmerkungen deiner Lehrperson"
      # Die Korrektur ersetzt die Rücklese-Ansicht der eigenen Antworten.
      refute html =~ "task-answers-editor-#{submission.id}"
    end

    test "füttert die Korrektur nie in den editierbaren Editor", %{
      conn: conn,
      task: task,
      teacher_scope: teacher_scope,
      student: student
    } do
      {:ok, task} =
        Tasky.Tasks.update_task(teacher_scope, task, %{solution_release_mode: "manual"})

      {:ok, submission} =
        Tasky.Tasks.get_or_create_submission(Scope.for_user(student), task.id)

      {:ok, submission} = Tasky.Tasks.complete_task(Scope.for_user(student), submission.id)

      corrected = %{
        "type" => "doc",
        "content" => [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "ANMERKUNG-LP"}]}
        ]
      }

      {:ok, _} =
        Tasky.Tasks.save_correction_content(teacher_scope, task, submission.id, corrected)

      {:ok, _} = Tasky.Tasks.release_solution(teacher_scope, task, submission.id)
      {:ok, _} = Tasky.Tasks.review_submission(teacher_scope, submission.id, "review_denied", %{})

      {:ok, _lv, html} = live(conn, ~p"/student/tasks/#{task.id}")

      # Beim Überarbeiten steht die Korrektur über dem Editor …
      assert html =~ "Mit den Anmerkungen deiner Lehrperson"
      assert html =~ "task-correction-viewer-#{submission.id}"

      # … aber der editierbare Editor bekommt weiterhin nur die eigenen
      # Antworten. Sonst würde der nächste Autosave die Anmerkungen der
      # Lehrperson als eigene Antwort zurückschreiben.
      assert html =~ ~s(id="task-answers-editor-#{submission.id}")
      [_before, editor_tag | _] = String.split(html, ~s(id="task-answers-editor-))
      refute editor_tag |> String.slice(0, 600) =~ "ANMERKUNG-LP"
    end

    test "wird live sichtbar, wenn die Lehrperson während der Sitzung freigibt", %{
      conn: conn,
      task: task,
      teacher_scope: teacher_scope,
      student: student
    } do
      {:ok, task} =
        Tasky.Tasks.update_task(teacher_scope, task, %{solution_release_mode: "manual"})

      {:ok, lv, html} = live(conn, ~p"/student/tasks/#{task.id}")
      refute html =~ "MUSTERLOESUNG"

      submission = Tasky.Tasks.get_submission_for_student(task.id, student.id)
      {:ok, _} = Tasky.Tasks.release_solution(teacher_scope, task, submission.id)

      assert render(lv) =~ "MUSTERLOESUNG"
    end
  end

  describe "Vergleichsansicht (Selbstkontrolle)" do
    setup %{student: student, course: course, task: task} do
      {:ok, _} = Courses.enroll_student(course.id, student.id)

      teacher_scope = Scope.for_user(Tasky.Repo.get!(Tasky.Accounts.User, task.user_id))

      # Zwei Antwortfelder: eines wird richtig beantwortet, eines falsch.
      skeleton = fn ->
        %{
          "type" => "doc",
          "content" =>
            Enum.map(["a1", "a2"], fn id ->
              %{
                "type" => "answerBlock",
                "attrs" => %{"answerId" => id},
                "content" => [%{"type" => "paragraph"}]
              }
            end)
        }
      end

      {:ok, task} = Tasky.Tasks.save_task_content(teacher_scope, task, skeleton.())

      filled =
        skeleton.()
        |> put_in(["content", Access.at(0), "content"], [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Bern"}]}
        ])
        |> put_in(["content", Access.at(1), "content"], [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Aare"}]}
        ])

      {:ok, task} = Tasky.Tasks.save_sample_solution(teacher_scope, task, filled)

      {:ok, task} =
        Tasky.Tasks.update_task(teacher_scope, task, %{solution_release_mode: "on_complete"})

      %{task: task, teacher_scope: teacher_scope, skeleton: skeleton}
    end

    defp answer_and_complete(student, task, skeleton, answers) do
      scope = Scope.for_user(student)
      {:ok, submission} = Tasky.Tasks.get_or_create_submission(scope, task.id)

      doc =
        Enum.reduce(Enum.with_index(answers), skeleton.(), fn {text, index}, acc ->
          put_in(acc, ["content", Access.at(index), "content"], [
            %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}
          ])
        end)

      {:ok, submission} = Tasky.Tasks.save_student_answers(scope, submission, doc)
      {:ok, submission} = Tasky.Tasks.complete_task(scope, submission.id)
      submission
    end

    test "macht das Prüfen zum Primary-Button, sobald die Musterlösung sichtbar ist", %{
      conn: conn,
      student: student,
      task: task,
      skeleton: skeleton
    } do
      answer_and_complete(student, task, skeleton, ["Bern", "Rhein"])

      {:ok, _lv, html} = live(conn, ~p"/student/tasks/#{task.id}")

      assert html =~ "Antworten prüfen und Musterlösung anzeigen"
      # «Weiter» tritt zurück: kein Emerald-Hintergrund mehr an diesem Link.
      refute html =~ ~r/bg-emerald-500[^"]*"[^>]*>\s*Weiter/
    end

    test "lässt Weiter den Primary-Button, wenn es keine Musterlösung zu sehen gibt", %{
      conn: conn,
      student: student,
      task: task,
      teacher_scope: teacher_scope,
      skeleton: skeleton
    } do
      {:ok, task} =
        Tasky.Tasks.update_task(teacher_scope, task, %{solution_release_mode: "never"})

      answer_and_complete(student, task, skeleton, ["Bern", "Rhein"])

      {:ok, _lv, html} = live(conn, ~p"/student/tasks/#{task.id}")

      refute html =~ "Antworten prüfen und Musterlösung anzeigen"
      assert html =~ "Weiter"
    end

    test "zeigt Verdikte, Musterlösung am Antwortfeld und die Trefferquote", %{
      conn: conn,
      student: student,
      task: task,
      skeleton: skeleton
    } do
      submission = answer_and_complete(student, task, skeleton, ["bern", "Rhein"])

      {:ok, _lv, html} = live(conn, ~p"/student/tasks/#{task.id}?preview=true&tab=musterloesung")

      # Beide Felder sind prüfbar; «bern» gilt (Gross-/Kleinschreibung wird
      # ignoriert), «Rhein» ist falsch.
      assert html =~ "1/2"
      assert html =~ "Deine Antworten im Vergleich"

      viewer = viewer_payload(html, "task-solution-viewer-#{submission.id}")
      assert viewer =~ "correct"
      assert viewer =~ "wrong"
      assert viewer =~ "solutionHint"
      # Die Musterlösung des falsch beantworteten Felds steht mit dabei.
      assert viewer =~ "Aare"
    end

    test "gibt nichts davon heraus, solange die Musterlösung nicht freigegeben ist", %{
      conn: conn,
      student: student,
      task: task,
      teacher_scope: teacher_scope,
      skeleton: skeleton
    } do
      {:ok, task} =
        Tasky.Tasks.update_task(teacher_scope, task, %{solution_release_mode: "manual"})

      answer_and_complete(student, task, skeleton, ["bern", "Rhein"])

      {:ok, _lv, html} = live(conn, ~p"/student/tasks/#{task.id}?preview=true&tab=musterloesung")

      refute html =~ "solutionHint"
      refute html =~ "Aare"
      refute html =~ "Deine Antworten im Vergleich"
    end

    test "prüft ein abgeschaltetes Feld nicht, zeigt dort aber die Musterlösung", %{
      conn: conn,
      student: student,
      task: task,
      teacher_scope: teacher_scope,
      skeleton: skeleton
    } do
      {:ok, task} = Tasky.Tasks.toggle_self_check(teacher_scope, task, "a2")

      submission = answer_and_complete(student, task, skeleton, ["Bern", "eigene Worte"])

      {:ok, _lv, html} = live(conn, ~p"/student/tasks/#{task.id}?preview=true&tab=musterloesung")

      # Nur noch ein Feld zählt in die Quote.
      assert html =~ "1/1"

      viewer = viewer_payload(html, "task-solution-viewer-#{submission.id}")
      refute viewer =~ "wrong"
      # Die Musterlösung erscheint trotzdem — das ist der Sinn der Ausnahme.
      assert viewer =~ "Aare"
    end

    # Das an den Read-only-Viewer übergebene Dokument, isoliert vom übrigen
    # HTML: sonst würde eine Assertion auch auf Treffer ausserhalb des Viewers
    # anschlagen.
    defp viewer_payload(html, id) do
      [_before, rest] = String.split(html, ~s(id="#{id}"), parts: 2)
      rest |> String.split("</div>", parts: 2) |> hd()
    end
  end

  test "autosave API rejects a non-enrolled student", %{conn: conn, task: task} do
    conn =
      put(conn, "/api/student/tasks/#{task.id}/answers", %{
        "content" => %{"type" => "doc", "content" => []}
      })

    assert json_response(conn, 404)
  end
end
