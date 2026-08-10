defmodule Tasky.CoursesDuplicateTest do
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
    course = course_fixture(scope: scope, attrs: %{name: "Original", description: "Beschreibung"})

    %{teacher: teacher, scope: scope, course: course}
  end

  defp tmp_file(content) do
    path = Path.join(System.tmp_dir!(), "upload_src_#{System.unique_integer([:positive])}")
    File.write!(path, content)
    path
  end

  defp image_upload do
    %Plug.Upload{path: tmp_file(@png_bytes), content_type: "image/png", filename: "bild.png"}
  end

  describe "duplicate_course/3" do
    test "copies the course itself under the given name", %{scope: scope, course: course} do
      assert {:ok, copy} = Courses.duplicate_course(scope, course, "Kopie von — Original")

      assert copy.id != course.id
      assert copy.name == "Kopie von — Original"
      assert copy.description == "Beschreibung"
      assert copy.teacher_id == scope.user.id
    end

    test "copies every learning unit with its attributes", %{scope: scope, course: course} do
      task_fixture(scope, %{
        name: "Einheit 1",
        position: 0,
        status: "published",
        course_id: course.id
      })

      task_fixture(scope, %{name: "Einheit 2", position: 1, course_id: course.id, locked: true})

      task_fixture(scope, %{
        name: "Vertiefung",
        position: 2,
        course_id: course.id,
        extended: true
      })

      assert {:ok, copy} = Courses.duplicate_course(scope, course, "Kopie")

      assert [one, two, three] = Tasks.list_tasks_by_course(copy.id)
      assert one.name == "Einheit 1"
      assert one.position == 0
      assert one.status == "published"
      refute one.locked
      assert two.name == "Einheit 2"
      assert two.locked

      # A voluntary extension must not be silently demoted to a mandatory unit.
      refute one.extended
      assert three.name == "Vertiefung"
      assert three.extended

      # The originals stay where they are.
      assert length(Tasks.list_tasks_by_course(course.id)) == 3
    end

    test "copies the content doc and takes its images along", %{scope: scope, course: course} do
      task = task_fixture(scope, %{name: "Mit Bild", position: 0, course_id: course.id})
      {:ok, url} = Tasky.Uploads.save_task_image(task.id, image_upload())
      filename = url |> String.split("/") |> List.last()

      doc = %{
        "type" => "doc",
        "content" => [
          %{"type" => "image", "attrs" => %{"src" => url, "alt" => "Bild"}},
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Hallo"}]}
        ]
      }

      {:ok, _task} = Tasks.save_task_content(scope, task, doc)

      assert {:ok, copy} = Courses.duplicate_course(scope, course, "Kopie")
      assert [copied_task] = Tasks.list_tasks_by_course(copy.id)

      assert [image_node, paragraph] = copied_task.content["content"]
      assert image_node["attrs"]["src"] == "/uploads/tasks/#{copied_task.id}/#{filename}"
      assert image_node["attrs"]["alt"] == "Bild"
      assert paragraph["content"] == [%{"type" => "text", "text" => "Hallo"}]

      # The copy owns its bytes, so deleting the original leaves it intact.
      assert {:ok, {{:file, _path}, "image/png"}} =
               Tasky.Uploads.fetch_task_image(copied_task.id, filename)

      {:ok, _} = Tasks.delete_task(scope, task)

      assert {:ok, {{:file, _path}, "image/png"}} =
               Tasky.Uploads.fetch_task_image(copied_task.id, filename)
    end

    test "copies attachments under fresh stored filenames", %{scope: scope, course: course} do
      task = task_fixture(scope, %{name: "Mit Anhang", position: 0, course_id: course.id})

      {:ok, stored} =
        Tasky.Uploads.save_task_attachment(task.id, tmp_file("bytes"), "arbeitsblatt.pdf")

      {:ok, attachment} =
        Tasks.create_task_attachment(
          scope,
          task,
          Map.put(stored, :original_name, "arbeitsblatt.pdf")
        )

      assert {:ok, copy} = Courses.duplicate_course(scope, course, "Kopie")
      assert [copied_task] = Tasks.list_tasks_by_course(copy.id)

      assert [copied_attachment] = Tasks.list_task_attachments(copied_task)
      assert copied_attachment.original_name == "arbeitsblatt.pdf"
      assert copied_attachment.content_type == attachment.content_type
      assert copied_attachment.size == attachment.size
      assert copied_attachment.stored_filename != attachment.stored_filename

      assert {:ok, {:file, _path}} =
               Tasky.Uploads.fetch_task_attachment(
                 copied_task.id,
                 copied_attachment.stored_filename
               )
    end

    test "copies upload fields", %{scope: scope, course: course} do
      task = task_fixture(scope, %{name: "Mit Abgabe", position: 0, course_id: course.id})

      {:ok, _field} =
        Tasks.create_task_upload_field(scope, task, %{
          "label" => "Word-Datei",
          "instruction" => "Bearbeitet hochladen",
          "allowed_types" => ["docx"],
          "required" => true
        })

      assert {:ok, copy} = Courses.duplicate_course(scope, course, "Kopie")
      assert [copied_task] = Tasks.list_tasks_by_course(copy.id)

      assert [field] = Tasks.list_task_upload_fields(copied_task)
      assert field.label == "Word-Datei"
      assert field.instruction == "Bearbeitet hochladen"
      assert field.allowed_types == ["docx"]
      assert field.required
    end

    test "leaves students and their submissions behind", %{scope: scope, course: course} do
      task = task_fixture(scope, %{name: "Einheit", position: 0, course_id: course.id})
      student = user_fixture(%{role: "student"})
      student_scope = user_scope_fixture(student)
      enroll_fixture(course, student)
      {:ok, _submission} = Tasks.get_or_create_submission(student_scope, task.id)

      assert {:ok, copy} = Courses.duplicate_course(scope, course, "Kopie")
      assert [copied_task] = Tasks.list_tasks_by_course(copy.id)

      assert Courses.list_enrolled_students(copy.id) == []
      assert Tasks.list_task_submissions(scope, copied_task.id) == []
    end

    test "an image referenced twice produces a single copy", %{scope: scope, course: course} do
      task = task_fixture(scope, %{name: "Zweimal", position: 0, course_id: course.id})
      {:ok, url} = Tasky.Uploads.save_task_image(task.id, image_upload())

      doc = %{
        "type" => "doc",
        "content" => [
          %{"type" => "image", "attrs" => %{"src" => url}},
          %{"type" => "image", "attrs" => %{"src" => url}}
        ]
      }

      {:ok, _task} = Tasks.save_task_content(scope, task, doc)

      assert {:ok, _copy, jobs} = Courses.duplicate_course_records(scope, course, "Kopie")
      assert length(jobs) == 2
      assert %{copied: 1, failed: []} = Tasky.Uploads.run_copies(jobs)
    end

    test "refuses a course of another teacher", %{course: course} do
      other = user_scope_fixture(user_fixture(%{role: "teacher"}))

      assert {:error, :unauthorized} = Courses.duplicate_course(other, course, "Kopie")
      assert Courses.list_courses(other) == []
    end

    test "an admin may duplicate a teacher's course", %{course: course} do
      admin = user_scope_fixture(user_fixture(%{role: "admin"}))

      assert {:ok, copy} = Courses.duplicate_course(admin, course, "Kopie")
      assert copy.teacher_id == admin.user.id
    end

    test "a duplicate of a catalog course is not itself in the catalog", %{
      scope: scope,
      course: course
    } do
      task_fixture(scope, %{name: "Einheit", position: 0, course_id: course.id})
      {:ok, published} = Courses.publish_to_catalog(scope, course)

      assert {:ok, copy} = Courses.duplicate_course(scope, published, "Kopie")
      assert is_nil(copy.catalog_published_at)
    end
  end

  describe "duplicate_course_records/3 — the storage boundary" do
    # Regression test for the production crash: the copies used to run inside
    # the transaction, so a file-heavy course held a DB connection across
    # dozens of R2 round trips until Postgrex killed it at 15 s.
    test "performs no storage I/O inside the transaction", %{scope: scope, course: course} do
      task = task_fixture(scope, %{name: "Mit Dateien", position: 0, course_id: course.id})
      {:ok, url} = Tasky.Uploads.save_task_image(task.id, image_upload())

      {:ok, _task} =
        Tasks.save_task_content(scope, task, %{
          "type" => "doc",
          "content" => [%{"type" => "image", "attrs" => %{"src" => url}}]
        })

      {:ok, stored} = Tasky.Uploads.save_task_attachment(task.id, tmp_file("bytes"), "a.pdf")

      {:ok, _} =
        Tasks.create_task_attachment(scope, task, Map.put(stored, :original_name, "a.pdf"))

      Tasky.ProbeStorage.install()

      assert {:ok, _copy, jobs} = Courses.duplicate_course_records(scope, course, "Kopie")
      # The load-bearing assertion: nothing can reach Storage.copy/2 from
      # inside Repo.transaction and still pass this.
      refute_receive {:storage_copy, _, _, _}
      assert length(jobs) == 2

      assert %{copied: 2, failed: []} = Tasky.Uploads.run_copies(jobs)
      assert_receive {:storage_copy, _, _, false}
      assert_receive {:storage_copy, _, _, false}
    end

    test "leaves references outside the task's own prefix untouched", %{
      scope: scope,
      course: course
    } do
      task = task_fixture(scope, %{name: "Fremde Pfade", position: 0, course_id: course.id})

      # An attachment path (one segment deeper), another unit's image, and an
      # exam image — none of these are this unit's content images.
      content = [
        %{"type" => "text", "text" => "/uploads/tasks/#{task.id}/attachments/x.pdf"},
        %{"type" => "text", "text" => "/uploads/tasks/999/other.png"},
        %{"type" => "text", "text" => "/uploads/exams/1/y.png"}
      ]

      {:ok, _task} =
        Tasks.save_task_content(scope, task, %{"type" => "doc", "content" => content})

      assert {:ok, copy, jobs} = Courses.duplicate_course_records(scope, course, "Kopie")
      assert jobs == []

      assert [copied_task] = Tasks.list_tasks_by_course(copy.id)
      assert copied_task.content["content"] == content
    end
  end

  describe "duplicate_course/3 when storage fails" do
    setup %{scope: scope, course: course} do
      task = task_fixture(scope, %{name: "Mit Dateien", position: 0, course_id: course.id})
      {:ok, url} = Tasky.Uploads.save_task_image(task.id, image_upload())
      filename = url |> String.split("/") |> List.last()

      {:ok, _task} =
        Tasks.save_task_content(scope, task, %{
          "type" => "doc",
          "content" => [%{"type" => "image", "attrs" => %{"src" => url}}]
        })

      {:ok, stored} =
        Tasky.Uploads.save_task_attachment(task.id, tmp_file("bytes"), "arbeitsblatt.pdf")

      {:ok, attachment} =
        Tasks.create_task_attachment(
          scope,
          task,
          Map.put(stored, :original_name, "arbeitsblatt.pdf")
        )

      %{task: task, filename: filename, attachment: attachment}
    end

    test "still returns the course and keeps every record", %{
      scope: scope,
      course: course,
      filename: filename
    } do
      Tasky.ProbeStorage.install(copy_result: {:error, :not_found})

      assert {:ok, copy} = Courses.duplicate_course(scope, course, "Kopie")
      assert [copied_task] = Tasks.list_tasks_by_course(copy.id)

      # The content URL points at the duplicate's own prefix regardless — the
      # destination key is deterministic, so it no longer waits on the copy.
      assert [image_node] = copied_task.content["content"]
      assert image_node["attrs"]["src"] == "/uploads/tasks/#{copied_task.id}/#{filename}"

      # An attachment whose bytes never arrived is visibly broken rather than
      # silently missing from the duplicate.
      assert [copied_attachment] = Tasks.list_task_attachments(copied_task)
      assert copied_attachment.original_name == "arbeitsblatt.pdf"

      assert {:error, :not_found} =
               Tasky.Uploads.fetch_task_attachment(
                 copied_task.id,
                 copied_attachment.stored_filename
               )
    end

    test "an adapter that raises cannot take the caller down", %{scope: scope, course: course} do
      Tasky.ProbeStorage.install(copy_result: :raise)

      assert {:ok, copy} = Courses.duplicate_course(scope, course, "Kopie")
      assert Process.alive?(self())
      assert [_copied_task] = Tasks.list_tasks_by_course(copy.id)
    end
  end
end
