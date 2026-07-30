defmodule Tasky.TasksContentTest do
  use Tasky.DataCase, async: false

  alias Tasky.Tasks
  alias Tasky.Tasks.TaskSubmission

  import Tasky.AccountsFixtures, only: [user_fixture: 1, user_scope_fixture: 1]
  import Tasky.TasksFixtures

  setup do
    dir = Path.join(System.tmp_dir!(), "tasky_uploads_test_#{System.unique_integer([:positive])}")
    prev = Application.get_env(:tasky, :uploads_dir)
    Application.put_env(:tasky, :uploads_dir, dir)

    on_exit(fn ->
      File.rm_rf(dir)
      if prev, do: Application.put_env(:tasky, :uploads_dir, prev)
    end)

    teacher = user_fixture(%{role: "teacher"})
    student = user_fixture(%{role: "student"})
    teacher_scope = user_scope_fixture(teacher)
    student_scope = user_scope_fixture(student)
    task = task_fixture(teacher_scope, %{status: "published"})

    %{
      teacher_scope: teacher_scope,
      student_scope: student_scope,
      task: task
    }
  end

  defp submission(student_scope, task) do
    {:ok, submission} = Tasks.get_or_create_submission(student_scope, task.id)
    submission
  end

  defp tmp_file(content) do
    path = Path.join(System.tmp_dir!(), "upload_src_#{System.unique_integer([:positive])}")
    File.write!(path, content)
    path
  end

  defp stored_submission_file_attrs(task, submission, content \\ "bytes") do
    {:ok, stored} =
      Tasky.Uploads.save_task_submission_file(
        task.id,
        submission.id,
        tmp_file(content),
        "antwort.pdf",
        ["pdf"]
      )

    Map.put(stored, :original_name, "antwort.pdf")
  end

  @doc_without_ids %{
    "type" => "doc",
    "content" => [
      %{"type" => "answerBlock", "content" => [%{"type" => "paragraph"}]}
    ]
  }

  describe "save_task_content/3" do
    test "saves the doc and assigns answer ids", %{teacher_scope: scope, task: task} do
      assert {:ok, task} = Tasks.save_task_content(scope, task, @doc_without_ids)

      assert %{"content" => [%{"type" => "answerBlock", "attrs" => %{"answerId" => id}}]} =
               task.content

      assert to_string(id) != ""
    end

    test "returns unauthorized for a non-owner", %{student_scope: other, task: task} do
      other_teacher_scope = user_scope_fixture(user_fixture(%{role: "teacher"}))

      assert {:error, :unauthorized} =
               Tasks.save_task_content(other_teacher_scope, task, @doc_without_ids)

      _ = other
    end
  end

  describe "save_student_answers/3" do
    test "saves the answer doc for the own editable submission", %{
      student_scope: scope,
      task: task
    } do
      submission = submission(scope, task)
      doc = %{"type" => "doc", "content" => []}

      assert {:ok, %TaskSubmission{content: ^doc}} =
               Tasks.save_student_answers(scope, submission, doc)
    end

    test "rejects another student's submission", %{student_scope: scope, task: task} do
      submission = submission(scope, task)
      other_scope = user_scope_fixture(user_fixture(%{role: "student"}))

      assert {:error, :unauthorized} =
               Tasks.save_student_answers(other_scope, submission, %{"type" => "doc"})
    end

    test "rejects once completed, allows again after review_denied", %{
      student_scope: scope,
      teacher_scope: teacher_scope,
      task: task
    } do
      submission = submission(scope, task)
      {:ok, completed} = Tasks.complete_task(scope, submission.id)

      assert {:error, :not_editable} =
               Tasks.save_student_answers(scope, completed, %{"type" => "doc"})

      {:ok, denied} =
        Tasks.review_submission(teacher_scope, completed.id, "review_denied", %{
          feedback: "Bitte nochmals"
        })

      assert {:ok, _} = Tasks.save_student_answers(scope, denied, %{"type" => "doc"})
    end
  end

  describe "complete_task/2" do
    test "completes an editable submission", %{student_scope: scope, task: task} do
      submission = submission(scope, task)

      assert {:ok, %TaskSubmission{status: "completed", completed_at: %DateTime{}}} =
               Tasks.complete_task(scope, submission.id)
    end

    test "is blocked while a required upload is missing", %{
      student_scope: scope,
      task: task
    } do
      {:ok, field} =
        Tasks.create_task_upload_field(task, %{
          "label" => "Abgabe",
          "allowed_types" => ["pdf"],
          "required" => true
        })

      submission = submission(scope, task)
      assert {:error, :missing_uploads} = Tasks.complete_task(scope, submission.id)
      assert [%{id: field_id}] = Tasks.missing_required_uploads(submission)
      assert field_id == field.id

      {:ok, _} =
        Tasks.put_submission_file(
          submission,
          field,
          stored_submission_file_attrs(task, submission)
        )

      assert Tasks.missing_required_uploads(submission) == []

      assert {:ok, %TaskSubmission{status: "completed"}} =
               Tasks.complete_task(scope, submission.id)
    end

    test "cannot complete twice", %{student_scope: scope, task: task} do
      submission = submission(scope, task)
      {:ok, _} = Tasks.complete_task(scope, submission.id)
      assert {:error, :not_editable} = Tasks.complete_task(scope, submission.id)
    end
  end

  describe "review_submission/4" do
    test "approves with feedback", %{student_scope: scope, teacher_scope: teacher, task: task} do
      submission = submission(scope, task)
      {:ok, _} = Tasks.complete_task(scope, submission.id)

      assert {:ok, reviewed} =
               Tasks.review_submission(teacher, submission.id, "review_approved", %{
                 feedback: "Gut gemacht"
               })

      assert reviewed.status == "review_approved"
      assert reviewed.feedback == "Gut gemacht"
      assert reviewed.graded_by_id == teacher.user.id
    end

    test "denying reopens editing and re-completion", %{
      student_scope: scope,
      teacher_scope: teacher,
      task: task
    } do
      submission = submission(scope, task)
      {:ok, _} = Tasks.complete_task(scope, submission.id)

      {:ok, denied} = Tasks.review_submission(teacher, submission.id, "review_denied")
      assert denied.status == "review_denied"

      assert {:ok, %TaskSubmission{status: "completed"}} =
               Tasks.complete_task(scope, submission.id)
    end

    test "students may not review", %{student_scope: scope, task: task} do
      submission = submission(scope, task)
      {:ok, _} = Tasks.complete_task(scope, submission.id)

      assert {:error, :unauthorized} =
               Tasks.review_submission(scope, submission.id, "review_approved")
    end
  end

  describe "attachments" do
    test "create, list in position order, delete removes bytes", %{task: task} do
      {:ok, stored} =
        Tasky.Uploads.save_task_attachment(task.id, tmp_file("doc"), "arbeitsblatt.pdf")

      {:ok, a1} =
        Tasks.create_task_attachment(task, Map.put(stored, :original_name, "arbeitsblatt.pdf"))

      {:ok, stored2} = Tasky.Uploads.save_task_attachment(task.id, tmp_file("doc2"), "b.pdf")

      {:ok, a2} =
        Tasks.create_task_attachment(task, Map.put(stored2, :original_name, "b.pdf"))

      assert [^a1, ^a2] = Tasks.list_task_attachments(task)
      assert a1.position < a2.position

      {:ok, {:file, path}} = Tasky.Uploads.fetch_task_attachment(task.id, a1.stored_filename)
      assert File.exists?(path)

      {:ok, _} = Tasks.delete_task_attachment(a1)
      refute File.exists?(path)
      assert [^a2] = Tasks.list_task_attachments(task)
    end
  end

  describe "upload fields" do
    test "requires at least one known type", %{task: task} do
      assert {:error, changeset} =
               Tasks.create_task_upload_field(task, %{"label" => "X", "allowed_types" => []})

      assert %{allowed_types: _} = errors_on(changeset)

      assert {:error, changeset} =
               Tasks.create_task_upload_field(task, %{
                 "label" => "X",
                 "allowed_types" => ["exe"]
               })

      assert %{allowed_types: _} = errors_on(changeset)
    end

    test "create appends, update changes, delete removes student files", %{
      student_scope: scope,
      task: task
    } do
      {:ok, f1} =
        Tasks.create_task_upload_field(task, %{"label" => "A", "allowed_types" => ["pdf"]})

      {:ok, f2} =
        Tasks.create_task_upload_field(task, %{"label" => "B", "allowed_types" => ["docx"]})

      assert f2.position > f1.position
      assert [^f1, ^f2] = Tasks.list_task_upload_fields(task)

      {:ok, f1} = Tasks.update_task_upload_field(f1, %{"required" => true})
      assert f1.required

      submission = submission(scope, task)
      attrs = stored_submission_file_attrs(task, submission)
      {:ok, file} = Tasks.put_submission_file(submission, f1, attrs)

      {:ok, {:file, path}} =
        Tasky.Uploads.fetch_task_submission_file(task.id, submission.id, file.stored_filename)

      assert File.exists?(path)

      {:ok, _} = Tasks.delete_task_upload_field(f1)
      refute File.exists?(path)
      assert Tasks.list_submission_files(submission) == []
      assert [^f2] = Tasks.list_task_upload_fields(task)
    end
  end

  describe "put_submission_file/3" do
    test "re-upload replaces the previous file and deletes its bytes", %{
      student_scope: scope,
      task: task
    } do
      {:ok, field} =
        Tasks.create_task_upload_field(task, %{"label" => "A", "allowed_types" => ["pdf"]})

      submission = submission(scope, task)

      {:ok, first} =
        Tasks.put_submission_file(
          submission,
          field,
          stored_submission_file_attrs(task, submission)
        )

      {:ok, {:file, first_path}} =
        Tasky.Uploads.fetch_task_submission_file(task.id, submission.id, first.stored_filename)

      {:ok, second} =
        Tasks.put_submission_file(
          submission,
          field,
          stored_submission_file_attrs(task, submission, "other bytes")
        )

      assert second.id == first.id
      refute File.exists?(first_path)
      assert [only] = Tasks.list_submission_files(submission)
      assert only.stored_filename == second.stored_filename
      assert Tasks.get_submission_file(submission, field.id).id == second.id
    end
  end
end
