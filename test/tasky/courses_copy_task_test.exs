defmodule Tasky.CoursesCopyTaskTest do
  use Tasky.DataCase, async: false

  alias Tasky.Courses
  alias Tasky.Tasks

  import Tasky.AccountsFixtures, only: [user_fixture: 1, user_scope_fixture: 1]
  import Tasky.CoursesFixtures
  import Tasky.TasksFixtures

  @png_bytes <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, "fake-image-data">>

  setup do
    dir = Path.join(System.tmp_dir!(), "tasky_uploads_test_#{System.unique_integer([:positive])}")
    prev = Application.get_env(:tasky, :uploads_dir)
    Application.put_env(:tasky, :uploads_dir, dir)

    on_exit(fn ->
      File.rm_rf(dir)
      if prev, do: Application.put_env(:tasky, :uploads_dir, prev)
    end)

    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)
    source_course = course_fixture(scope: scope, attrs: %{name: "Klasse 2a"})
    target_course = course_fixture(scope: scope, attrs: %{name: "Klasse 2b"})

    %{scope: scope, source_course: source_course, target_course: target_course}
  end

  defp tmp_file(content) do
    path = Path.join(System.tmp_dir!(), "upload_src_#{System.unique_integer([:positive])}")
    File.write!(path, content)
    path
  end

  defp image_upload do
    %Plug.Upload{path: tmp_file(@png_bytes), content_type: "image/png", filename: "bild.png"}
  end

  # Läuft die Datei-Kopien, die `copy_task_into_courses/3` nur plant — die
  # Web-Schicht tut dasselbe über `Tasky.Courses.DuplicateRunner`.
  defp run_jobs(jobs), do: Tasky.Uploads.run_copies(jobs)

  describe "copy_task_into_courses/3" do
    test "appends the copy at the end of the target course", ctx do
      %{scope: scope, source_course: source, target_course: target} = ctx

      task_fixture(scope, %{name: "Bestehend A", position: 0, course_id: target.id})
      task_fixture(scope, %{name: "Bestehend B", position: 1, course_id: target.id})
      source_task = task_fixture(scope, %{name: "Kapitel 3", position: 7, course_id: source.id})

      assert {:ok, [copy], []} = Courses.copy_task_into_courses(scope, source_task, [target.id])

      assert copy.course_id == target.id
      assert copy.name == "Kapitel 3"
      assert copy.position == 2

      assert ["Bestehend A", "Bestehend B", "Kapitel 3"] =
               target.id |> Tasks.list_tasks_by_course() |> Enum.map(& &1.name)

      # Die Quelle bleibt, wo sie ist.
      assert [%{id: id, position: 7}] = Tasks.list_tasks_by_course(source.id)
      assert id == source_task.id
    end

    test "starts at position 0 in an empty target course", ctx do
      %{scope: scope, source_course: source, target_course: target} = ctx
      source_task = task_fixture(scope, %{name: "Erste", position: 4, course_id: source.id})

      assert {:ok, [copy], []} = Courses.copy_task_into_courses(scope, source_task, [target.id])
      assert copy.position == 0
    end

    test "the copy arrives as an unpublished, unlocked draft", ctx do
      %{scope: scope, source_course: source, target_course: target} = ctx

      source_task =
        task_fixture(scope, %{
          name: "Kapitel 3",
          position: 0,
          course_id: source.id,
          status: "published",
          locked: true,
          extended: true
        })

      {:ok, source_task} =
        Tasks.update_task(scope, source_task, %{solution_release_mode: "on_complete"})

      assert {:ok, [copy], []} = Courses.copy_task_into_courses(scope, source_task, [target.id])

      assert copy.status == "draft"
      refute copy.locked
      assert copy.solution_release_mode == "never"

      # `extended` ist Inhalt, keine Freigabe — der freiwillige Zusatzauftrag
      # bleibt einer.
      assert copy.extended
      assert copy.name == "Kapitel 3"
      assert copy.user_id == scope.user.id
    end

    test "copies the content doc and takes its images along", ctx do
      %{scope: scope, source_course: source, target_course: target} = ctx

      source_task = task_fixture(scope, %{name: "Mit Bild", position: 0, course_id: source.id})
      {:ok, url} = Tasky.Uploads.save_task_image(source_task.id, image_upload())
      filename = url |> String.split("/") |> List.last()

      doc = %{
        "type" => "doc",
        "content" => [
          %{"type" => "image", "attrs" => %{"src" => url, "alt" => "Bild"}},
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Hallo"}]}
        ]
      }

      {:ok, source_task} = Tasks.save_task_content(scope, source_task, doc)

      assert {:ok, [copy], jobs} = Courses.copy_task_into_courses(scope, source_task, [target.id])
      assert [%{src: _, dest: _}] = jobs
      run_jobs(jobs)

      assert [image_node, paragraph] = copy.content["content"]
      assert image_node["attrs"]["src"] == "/uploads/tasks/#{copy.id}/#{filename}"
      assert image_node["attrs"]["alt"] == "Bild"
      assert paragraph["content"] == [%{"type" => "text", "text" => "Hallo"}]

      # Die Kopie besitzt ihre Bytes: das Löschen der Quelle lässt sie stehen.
      {:ok, _} = Tasks.delete_task(scope, source_task)

      assert {:ok, {{:file, _path}, "image/png"}} =
               Tasky.Uploads.fetch_task_image(copy.id, filename)
    end

    test "copies the sample solution, attachments, solution files and upload fields", ctx do
      %{scope: scope, source_course: source, target_course: target} = ctx

      source_task = task_fixture(scope, %{name: "Voll", position: 0, course_id: source.id})

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

      {:ok, source_task} = Tasks.save_task_content(scope, source_task, doc)

      filled =
        put_in(doc, ["content", Access.at(0), "content"], [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Lösung"}]}
        ])

      {:ok, source_task} = Tasks.save_sample_solution(scope, source_task, filled)

      {:ok, stored} =
        Tasky.Uploads.save_task_attachment(source_task.id, tmp_file("bytes"), "blatt.pdf")

      {:ok, attachment} =
        Tasks.create_task_attachment(
          scope,
          source_task,
          Map.put(stored, :original_name, "blatt.pdf")
        )

      {:ok, solution_stored} =
        Tasky.Uploads.save_task_solution_file(source_task.id, tmp_file("bytes"), "loesung.docx")

      {:ok, solution_file} =
        Tasks.create_task_solution_file(
          scope,
          source_task,
          Map.put(solution_stored, :original_name, "loesung.docx")
        )

      {:ok, _field} =
        Tasks.create_task_upload_field(scope, source_task, %{
          "label" => "Word-Datei",
          "instruction" => "Bearbeitet hochladen",
          "allowed_types" => ["docx"],
          "required" => true
        })

      assert {:ok, [copy], jobs} = Courses.copy_task_into_courses(scope, source_task, [target.id])
      run_jobs(jobs)

      assert copy.sample_solution["a1"] == [
               %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Lösung"}]}
             ]

      assert [copied_attachment] = Tasks.list_task_attachments(copy)
      assert copied_attachment.original_name == "blatt.pdf"
      assert copied_attachment.stored_filename != attachment.stored_filename

      assert {:ok, {:file, _}} =
               Tasky.Uploads.fetch_task_attachment(copy.id, copied_attachment.stored_filename)

      assert [copied_solution] = Tasks.list_task_solution_files(copy)
      assert copied_solution.original_name == "loesung.docx"
      assert copied_solution.stored_filename != solution_file.stored_filename

      assert {:ok, {:file, _}} =
               Tasky.Uploads.fetch_task_solution_file(copy.id, copied_solution.stored_filename)

      assert [copied_field] = Tasks.list_task_upload_fields(copy)
      assert copied_field.label == "Word-Datei"
      assert copied_field.instruction == "Bearbeitet hochladen"
      assert copied_field.allowed_types == ["docx"]
      assert copied_field.required
    end

    test "leaves the students' submissions behind", ctx do
      %{scope: scope, source_course: source, target_course: target} = ctx

      source_task =
        task_fixture(scope, %{
          name: "Einheit",
          position: 0,
          course_id: source.id,
          status: "published"
        })

      student = user_fixture(%{role: "student"})
      student_scope = user_scope_fixture(student)
      enroll_fixture(source, student)
      {:ok, _submission} = Tasks.get_or_create_submission(student_scope, source_task.id)

      assert {:ok, [copy], []} = Courses.copy_task_into_courses(scope, source_task, [target.id])

      assert Tasks.list_task_submissions(scope, copy.id) == []
      assert Tasks.list_task_submissions(scope, source_task.id) != []
    end

    test "copies into several courses in one call, each at its own end", ctx do
      %{scope: scope, source_course: source, target_course: target} = ctx
      other = course_fixture(scope: scope, attrs: %{name: "Klasse 2c"})

      task_fixture(scope, %{name: "Bestehend", position: 0, course_id: target.id})
      source_task = task_fixture(scope, %{name: "Kapitel 3", position: 0, course_id: source.id})

      assert {:ok, [first, second], []} =
               Courses.copy_task_into_courses(scope, source_task, [target.id, other.id])

      assert first.course_id == target.id
      assert first.position == 1
      assert second.course_id == other.id
      assert second.position == 0
    end

    test "copying twice produces two units — no overwrite", ctx do
      %{scope: scope, source_course: source, target_course: target} = ctx
      source_task = task_fixture(scope, %{name: "Kapitel 3", position: 0, course_id: source.id})

      assert {:ok, [first], []} = Courses.copy_task_into_courses(scope, source_task, [target.id])
      assert {:ok, [second], []} = Courses.copy_task_into_courses(scope, source_task, [target.id])

      assert first.id != second.id
      assert second.position == first.position + 1
      assert length(Tasks.list_tasks_by_course(target.id)) == 2
    end

    test "a duplicate course id in the list copies only once", ctx do
      %{scope: scope, source_course: source, target_course: target} = ctx
      source_task = task_fixture(scope, %{name: "Kapitel 3", position: 0, course_id: source.id})

      assert {:ok, [_copy], []} =
               Courses.copy_task_into_courses(scope, source_task, [target.id, target.id])

      assert length(Tasks.list_tasks_by_course(target.id)) == 1
    end

    test "refuses a target course owned by someone else and writes nothing", ctx do
      %{scope: scope, source_course: source, target_course: target} = ctx

      foreign = course_fixture(attrs: %{name: "Fremd"})
      source_task = task_fixture(scope, %{name: "Kapitel 3", position: 0, course_id: source.id})

      assert {:error, :unauthorized} =
               Courses.copy_task_into_courses(scope, source_task, [target.id, foreign.id])

      # Alles oder nichts — der erlaubte Zielkurs bleibt leer.
      assert Tasks.list_tasks_by_course(target.id) == []
      assert Tasks.list_tasks_by_course(foreign.id) == []
    end

    test "refuses a target course that does not exist", ctx do
      %{scope: scope, source_course: source} = ctx
      source_task = task_fixture(scope, %{name: "Kapitel 3", position: 0, course_id: source.id})

      assert {:error, :unauthorized} =
               Courses.copy_task_into_courses(scope, source_task, [-1])
    end

    test "refuses a source unit owned by someone else", ctx do
      %{target_course: target} = ctx

      other_scope = user_scope_fixture(user_fixture(%{role: "teacher"}))
      other_course = course_fixture(scope: other_scope)

      foreign_task =
        task_fixture(other_scope, %{name: "Fremd", position: 0, course_id: other_course.id})

      scope = ctx.scope

      assert {:error, :unauthorized} =
               Courses.copy_task_into_courses(scope, foreign_task, [target.id])

      assert Tasks.list_tasks_by_course(target.id) == []
    end

    test "an empty target list copies nothing", ctx do
      %{scope: scope, source_course: source} = ctx
      source_task = task_fixture(scope, %{name: "Kapitel 3", position: 0, course_id: source.id})

      assert {:ok, [], []} = Courses.copy_task_into_courses(scope, source_task, [])
    end
  end
end
