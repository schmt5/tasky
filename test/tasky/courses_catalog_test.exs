defmodule Tasky.CoursesCatalogTest do
  use Tasky.DataCase, async: false

  alias Tasky.Courses
  alias Tasky.Courses.Course
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

    author = user_scope_fixture(user_fixture(%{role: "teacher"}))
    importer = user_scope_fixture(user_fixture(%{role: "teacher"}))

    course =
      course_fixture(scope: author, attrs: %{name: "Original", description: "Beschreibung"})

    %{author: author, importer: importer, course: course}
  end

  defp tmp_file(content) do
    path = Path.join(System.tmp_dir!(), "upload_src_#{System.unique_integer([:positive])}")
    File.write!(path, content)
    path
  end

  defp image_upload do
    %Plug.Upload{path: tmp_file(@png_bytes), content_type: "image/png", filename: "bild.png"}
  end

  describe "publish_to_catalog/2" do
    test "puts the course into the catalog", %{author: author, course: course} do
      task_fixture(author, %{name: "Einheit", position: 0, course_id: course.id})

      assert {:ok, published} = Courses.publish_to_catalog(author, course)
      assert %DateTime{} = published.catalog_published_at
      assert Course.catalog_published?(published)
    end

    test "refreshes the date when published again", %{author: author, course: course} do
      task_fixture(author, %{name: "Einheit", position: 0, course_id: course.id})

      {:ok, first} = Courses.publish_to_catalog(author, course)
      earlier = DateTime.add(first.catalog_published_at, -60, :second)

      stale =
        first
        |> Ecto.Changeset.change(catalog_published_at: earlier)
        |> Repo.update!()

      assert {:ok, again} = Courses.publish_to_catalog(author, stale)
      assert DateTime.compare(again.catalog_published_at, earlier) == :gt
    end

    test "refuses a course without learning units", %{author: author, course: course} do
      assert {:error, :no_units} = Courses.publish_to_catalog(author, course)
      assert is_nil(Repo.reload!(course).catalog_published_at)
    end

    test "refuses another teacher's course", %{importer: importer, author: author, course: course} do
      task_fixture(author, %{name: "Einheit", position: 0, course_id: course.id})

      assert {:error, :unauthorized} = Courses.publish_to_catalog(importer, course)
    end

    test "an admin may publish a teacher's course", %{author: author, course: course} do
      task_fixture(author, %{name: "Einheit", position: 0, course_id: course.id})
      admin = user_scope_fixture(user_fixture(%{role: "admin"}))

      assert {:ok, published} = Courses.publish_to_catalog(admin, course)
      assert Course.catalog_published?(published)
    end
  end

  describe "unpublish_from_catalog/2" do
    test "takes the course out of the catalog", %{author: author, course: course} do
      published = catalog_course_fixture(scope: author, course: course)

      assert {:ok, unpublished} = Courses.unpublish_from_catalog(author, published)
      assert is_nil(unpublished.catalog_published_at)
      refute Course.catalog_published?(unpublished)
    end

    test "refuses another teacher's course", %{author: author, importer: importer, course: course} do
      published = catalog_course_fixture(scope: author, course: course)

      assert {:error, :unauthorized} = Courses.unpublish_from_catalog(importer, published)
      assert Repo.reload!(published).catalog_published_at
    end
  end

  describe "list_catalog_courses/1" do
    test "lists only published courses, newest first", %{author: author, importer: importer} do
      older = catalog_course_fixture(scope: author)
      newer = catalog_course_fixture(scope: author)

      # Push the first one back so the ordering is unambiguous.
      older
      |> Ecto.Changeset.change(
        catalog_published_at: DateTime.add(older.catalog_published_at, -60, :second)
      )
      |> Repo.update!()

      _unpublished = course_fixture(scope: author, attrs: %{name: "Privat"})

      assert [first, second] = Courses.list_catalog_courses(importer)
      assert first.id == newer.id
      assert second.id == older.id
    end

    test "fills unit_count and preloads the teacher", %{author: author, importer: importer} do
      course = course_fixture(scope: author, attrs: %{name: "Drei Einheiten"})
      for i <- 0..2, do: task_fixture(author, %{name: "E#{i}", position: i, course_id: course.id})
      published = catalog_course_fixture(scope: author, course: course)

      assert [listed] = Courses.list_catalog_courses(importer)
      assert listed.id == published.id
      assert listed.unit_count == 3
      assert listed.teacher.id == author.user.id
    end

    test "an admin sees the catalog too", %{author: author} do
      published = catalog_course_fixture(scope: author)
      admin = user_scope_fixture(user_fixture(%{role: "admin"}))

      assert [listed] = Courses.list_catalog_courses(admin)
      assert listed.id == published.id
    end

    test "students see nothing", %{author: author} do
      catalog_course_fixture(scope: author)
      student = user_scope_fixture(user_fixture(%{role: "student"}))

      assert Courses.list_catalog_courses(student) == []
    end
  end

  describe "get_catalog_course!/2" do
    test "returns another teacher's published course", %{author: author, importer: importer} do
      published = catalog_course_fixture(scope: author)

      assert fetched = Courses.get_catalog_course!(importer, published.id)
      assert fetched.id == published.id
      assert fetched.teacher.id == author.user.id
    end

    test "raises for a course that is not in the catalog", %{author: author, importer: importer} do
      private = course_fixture(scope: author, attrs: %{name: "Privat"})

      assert_raise Ecto.NoResultsError, fn ->
        Courses.get_catalog_course!(importer, private.id)
      end
    end

    test "raises for a student", %{author: author} do
      published = catalog_course_fixture(scope: author)
      student = user_scope_fixture(user_fixture(%{role: "student"}))

      assert_raise Ecto.NoResultsError, fn ->
        Courses.get_catalog_course!(student, published.id)
      end
    end

    test "raises for an unknown id", %{importer: importer} do
      assert_raise Ecto.NoResultsError, fn -> Courses.get_catalog_course!(importer, -1) end
    end
  end

  describe "import_catalog_course/3" do
    test "another teacher may import and owns the copy", %{
      author: author,
      importer: importer,
      course: course
    } do
      task_fixture(author, %{name: "Einheit", position: 0, course_id: course.id})
      published = catalog_course_fixture(scope: author, course: course)

      assert {:ok, copy} = Courses.import_catalog_course(importer, published.id, published.name)

      assert copy.id != published.id
      assert copy.name == "Original"
      assert copy.description == "Beschreibung"
      assert copy.teacher_id == importer.user.id
    end

    test "every copied unit starts as an unlocked draft", %{
      author: author,
      importer: importer,
      course: course
    } do
      task_fixture(author, %{
        name: "Freigegeben",
        position: 0,
        status: "published",
        locked: true,
        course_id: course.id
      })

      task_fixture(author, %{
        name: "Archiviert",
        position: 1,
        status: "archived",
        course_id: course.id
      })

      task_fixture(author, %{
        name: "Vertiefung",
        position: 2,
        status: "published",
        extended: true,
        course_id: course.id
      })

      published = catalog_course_fixture(scope: author, course: course)

      assert {:ok, copy} = Courses.import_catalog_course(importer, published.id, "Übernommen")

      assert [one, two, three] = Tasks.list_tasks_by_course(copy.id)

      for unit <- [one, two, three] do
        assert unit.status == "draft"
        refute unit.locked
        assert unit.user_id == importer.user.id
      end

      assert one.name == "Freigegeben"
      assert two.name == "Archiviert"

      # `extended` is a property of the content, not a release state.
      assert three.name == "Vertiefung"
      assert three.extended
      refute one.extended
    end

    test "leaves the source untouched", %{author: author, importer: importer, course: course} do
      task_fixture(author, %{
        name: "Freigegeben",
        position: 0,
        status: "published",
        locked: true,
        course_id: course.id
      })

      published = catalog_course_fixture(scope: author, course: course)

      assert {:ok, _copy} = Courses.import_catalog_course(importer, published.id, "Übernommen")

      assert Repo.reload!(published).catalog_published_at
      assert [original] = Tasks.list_tasks_by_course(published.id)
      assert original.status == "published"
      assert original.locked
      assert original.user_id == author.user.id
    end

    test "the copy is neither published to the catalog nor open for feedback", %{
      author: author,
      importer: importer,
      course: course
    } do
      {:ok, course} = Courses.update_course(author, course, %{feedback_box_enabled: true})
      published = catalog_course_fixture(scope: author, course: course)

      assert {:ok, copy} = Courses.import_catalog_course(importer, published.id, "Übernommen")

      assert is_nil(copy.catalog_published_at)
      refute copy.feedback_box_enabled
      assert is_nil(copy.share_slug)
    end

    test "keeps the sample solution but resets its release mode", %{
      author: author,
      importer: importer,
      course: course
    } do
      task = task_fixture(author, %{name: "Mit Lösung", position: 0, course_id: course.id})

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

      {:ok, task} = Tasks.save_task_content(author, task, doc)
      {:ok, task} = Tasks.update_task(author, task, %{solution_release_mode: "on_complete"})

      filled =
        put_in(doc, ["content", Access.at(0), "content"], [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Lösung"}]}
        ])

      {:ok, _task} = Tasks.save_sample_solution(author, task, filled)

      published = catalog_course_fixture(scope: author, course: course)

      assert {:ok, copy} = Courses.import_catalog_course(importer, published.id, "Übernommen")
      assert [copied_task] = Tasks.list_tasks_by_course(copy.id)

      # Die Lösung ist Inhalt und reist mit …
      assert copied_task.sample_solution["a1"] == [
               %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Lösung"}]}
             ]

      # … der Freigabe-Zeitpunkt ist es nicht: die importierende Lehrperson
      # entscheidet für ihre Klasse.
      assert copied_task.solution_release_mode == "never"
    end

    test "copies solution files", %{author: author, importer: importer, course: course} do
      task = task_fixture(author, %{name: "Mit Lösungsdatei", position: 0, course_id: course.id})

      {:ok, stored} =
        Tasky.Uploads.save_task_solution_file(task.id, tmp_file("bytes"), "loesung.docx")

      {:ok, _} =
        Tasks.create_task_solution_file(
          author,
          task,
          Map.put(stored, :original_name, "loesung.docx")
        )

      published = catalog_course_fixture(scope: author, course: course)

      assert {:ok, copy} = Courses.import_catalog_course(importer, published.id, "Übernommen")
      assert [copied_task] = Tasks.list_tasks_by_course(copy.id)

      assert [copied_file] = Tasks.list_task_solution_files(copied_task)
      assert copied_file.original_name == "loesung.docx"
      assert copied_file.stored_filename != stored.stored_filename
    end

    test "copies content images, attachments and upload fields", %{
      author: author,
      importer: importer,
      course: course
    } do
      task = task_fixture(author, %{name: "Mit Dateien", position: 0, course_id: course.id})
      {:ok, url} = Tasky.Uploads.save_task_image(task.id, image_upload())

      {:ok, _task} =
        Tasks.save_task_content(author, task, %{
          "type" => "doc",
          "content" => [%{"type" => "image", "attrs" => %{"src" => url}}]
        })

      {:ok, stored} = Tasky.Uploads.save_task_attachment(task.id, tmp_file("bytes"), "a.pdf")

      {:ok, _} =
        Tasks.create_task_attachment(author, task, Map.put(stored, :original_name, "a.pdf"))

      {:ok, _field} =
        Tasks.create_task_upload_field(author, task, %{
          "label" => "Abgabe",
          "allowed_types" => ["pdf"],
          "required" => true
        })

      published = catalog_course_fixture(scope: author, course: course)

      assert {:ok, copy} = Courses.import_catalog_course(importer, published.id, "Übernommen")
      assert [copied] = Tasks.list_tasks_by_course(copy.id)

      # The image src was rewritten to the copy's own prefix and the bytes came along.
      assert %{"content" => [%{"attrs" => %{"src" => new_url}}]} = copied.content
      assert new_url =~ "/uploads/tasks/#{copied.id}/"
      refute new_url == url

      assert [attachment] = Tasks.list_task_attachments(copied)
      assert attachment.original_name == "a.pdf"
      refute attachment.stored_filename == stored.stored_filename

      assert [field] = Tasks.list_task_upload_fields(copied)
      assert field.label == "Abgabe"
      assert field.required
    end

    test "refuses a course that is not in the catalog", %{
      author: author,
      importer: importer,
      course: course
    } do
      task_fixture(author, %{name: "Einheit", position: 0, course_id: course.id})

      assert {:error, :not_found} = Courses.import_catalog_course(importer, course.id, "Kopie")
      assert Courses.list_courses(importer) == []
    end

    test "refuses a student", %{author: author} do
      published = catalog_course_fixture(scope: author)
      student = user_scope_fixture(user_fixture(%{role: "student"}))

      assert {:error, :unauthorized} =
               Courses.import_catalog_course(student, published.id, "Kopie")
    end

    test "refuses an unknown id", %{importer: importer} do
      assert {:error, :not_found} = Courses.import_catalog_course(importer, -1, "Kopie")
    end

    # Pins the id-not-struct signature: the preview page may sit open for
    # minutes, so the publication is re-read at import time.
    test "refuses after the author unpublished", %{author: author, importer: importer} do
      published = catalog_course_fixture(scope: author)
      {:ok, _} = Courses.unpublish_from_catalog(author, published)

      assert {:error, :not_found} =
               Courses.import_catalog_course(importer, published.id, "Kopie")
    end
  end

  describe "import_catalog_course_records/3 — the storage boundary" do
    test "performs no storage I/O inside the transaction", %{
      author: author,
      importer: importer,
      course: course
    } do
      task = task_fixture(author, %{name: "Mit Dateien", position: 0, course_id: course.id})
      {:ok, url} = Tasky.Uploads.save_task_image(task.id, image_upload())

      {:ok, _task} =
        Tasks.save_task_content(author, task, %{
          "type" => "doc",
          "content" => [%{"type" => "image", "attrs" => %{"src" => url}}]
        })

      {:ok, stored} = Tasky.Uploads.save_task_attachment(task.id, tmp_file("bytes"), "a.pdf")

      {:ok, _} =
        Tasks.create_task_attachment(author, task, Map.put(stored, :original_name, "a.pdf"))

      published = catalog_course_fixture(scope: author, course: course)

      Tasky.ProbeStorage.install()

      assert {:ok, _copy, jobs} =
               Courses.import_catalog_course_records(importer, published.id, "Übernommen")

      refute_receive {:storage_copy, _, _, _}
      assert length(jobs) == 2

      assert %{copied: 2, failed: []} = Tasky.Uploads.run_copies(jobs)
      assert_receive {:storage_copy, _, _, false}
      assert_receive {:storage_copy, _, _, false}
    end
  end
end
