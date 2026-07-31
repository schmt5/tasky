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

      assert {:ok, copy} = Courses.duplicate_course(scope, course, "Kopie")

      assert [one, two] = Tasks.list_tasks_by_course(copy.id)
      assert one.name == "Einheit 1"
      assert one.position == 0
      assert one.status == "published"
      refute one.locked
      assert two.name == "Einheit 2"
      assert two.locked

      # The originals stay where they are.
      assert length(Tasks.list_tasks_by_course(course.id)) == 2
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
        Tasks.create_task_attachment(task, Map.put(stored, :original_name, "arbeitsblatt.pdf"))

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
        Tasks.create_task_upload_field(task, %{
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
  end
end
