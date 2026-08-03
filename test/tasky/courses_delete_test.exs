defmodule Tasky.CoursesDeleteTest do
  use Tasky.DataCase, async: false

  alias Tasky.Courses
  alias Tasky.Tasks
  alias Tasky.Uploads

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
    course = course_fixture(scope: scope, attrs: %{name: "Original"})

    %{dir: dir, scope: scope, course: course}
  end

  defp tmp_file(content) do
    path = Path.join(System.tmp_dir!(), "upload_src_#{System.unique_integer([:positive])}")
    File.write!(path, content)
    path
  end

  defp image_upload do
    %Plug.Upload{path: tmp_file(@png_bytes), content_type: "image/png", filename: "bild.png"}
  end

  # A unit carrying both kinds of stored file.
  defp unit_with_files(scope, course, position) do
    task =
      task_fixture(scope, %{name: "Einheit #{position}", position: position, course_id: course.id})

    {:ok, url} = Uploads.save_task_image(task.id, image_upload())
    filename = url |> String.split("/") |> List.last()

    {:ok, stored} = Uploads.save_task_attachment(task.id, tmp_file("bytes"), "auftrag.pdf")

    {:ok, attachment} =
      Tasks.create_task_attachment(task, Map.put(stored, :original_name, "auftrag.pdf"))

    %{task: task, image: filename, attachment: attachment}
  end

  describe "delete_course/1" do
    test "removes the stored files of every learning unit", %{scope: scope, course: course} do
      one = unit_with_files(scope, course, 0)
      two = unit_with_files(scope, course, 1)

      assert {:ok, {:file, _}} = Uploads.fetch_task_attachment(one.task.id, stored(one))
      assert {:ok, {{:file, _}, _}} = Uploads.fetch_task_image(two.task.id, two.image)

      assert {:ok, _} = Courses.delete_course(course)

      # The cascade removes the rows; these assertions are about the bytes,
      # which nothing else in the delete path would have cleared.
      for unit <- [one, two] do
        assert {:error, :not_found} = Uploads.fetch_task_image(unit.task.id, unit.image)
        assert {:error, :not_found} = Uploads.fetch_task_attachment(unit.task.id, stored(unit))
      end
    end

    test "leaves the upload directory with no trace of the course", %{
      dir: dir,
      scope: scope,
      course: course
    } do
      unit = unit_with_files(scope, course, 0)

      assert File.dir?(Path.join([dir, "tasks", to_string(unit.task.id)]))

      assert {:ok, _} = Courses.delete_course(course)

      refute File.exists?(Path.join([dir, "tasks", to_string(unit.task.id)]))
    end

    test "does not touch the files of another course", %{scope: scope, course: course} do
      doomed = unit_with_files(scope, course, 0)

      other = course_fixture(scope: scope, attrs: %{name: "Bleibt"})
      kept = unit_with_files(scope, other, 0)

      assert {:ok, _} = Courses.delete_course(course)

      assert {:error, :not_found} = Uploads.fetch_task_image(doomed.task.id, doomed.image)
      assert {:ok, {{:file, _}, _}} = Uploads.fetch_task_image(kept.task.id, kept.image)
      assert {:ok, {:file, _}} = Uploads.fetch_task_attachment(kept.task.id, stored(kept))
    end

    test "deletes the rows as before", %{scope: scope, course: course} do
      unit = unit_with_files(scope, course, 0)

      assert {:ok, _} = Courses.delete_course(course)

      assert Tasks.list_tasks_by_course(course.id) == []
      assert Repo.get(Tasky.Tasks.Task, unit.task.id) == nil
      assert Repo.get(Tasky.Courses.Course, course.id) == nil
    end

    test "a course without units deletes cleanly", %{course: course} do
      assert {:ok, _} = Courses.delete_course(course)
      assert Repo.get(Tasky.Courses.Course, course.id) == nil
    end

    test "a storage adapter that raises does not take the caller down", %{
      scope: scope,
      course: course
    } do
      unit_with_files(scope, course, 0)
      Tasky.ProbeStorage.install(delete_prefix_result: :raise)

      assert {:ok, _} = Courses.delete_course(course)
      assert Process.alive?(self())
      assert Repo.get(Tasky.Courses.Course, course.id) == nil
    end
  end

  defp stored(%{attachment: attachment}), do: attachment.stored_filename
end
