defmodule Tasky.ExamsTest do
  use Tasky.DataCase, async: false

  import Tasky.ExamsFixtures

  alias Tasky.Exams

  defp enrollment_attrs, do: valid_enrollment_attrs()

  defp sample_doc(text) do
    %{
      "type" => "doc",
      "content" => [
        %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}
      ]
    }
  end

  describe "create_exam_submission/2" do
    test "enrolls when the exam is open" do
      exam = exam_fixture(status: "open")

      assert {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())
      assert submission.firstname == "Max"
      assert submission.exam_token
      refute submission.submitted
    end

    test "enrolls when the exam is already running" do
      exam = exam_fixture(status: "running")

      assert {:ok, _submission} = Exams.create_exam_submission(exam, enrollment_attrs())
    end

    test "rejects enrollment for draft and finished exams" do
      assert {:error, :exam_not_open} =
               Exams.create_exam_submission(exam_fixture(status: "draft"), enrollment_attrs())

      assert {:error, :exam_not_open} =
               Exams.create_exam_submission(exam_fixture(status: "finished"), enrollment_attrs())
    end
  end

  describe "update_exam_submission_content/2" do
    test "saves content while the exam is running" do
      exam = exam_fixture(status: "running")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())

      doc = sample_doc("Meine Antwort")
      assert {:ok, updated} = Exams.update_exam_submission_content(submission, doc)
      assert updated.content == doc
    end

    test "rejects saves once the exam is finished" do
      exam = exam_fixture(status: "running")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())
      {:ok, _exam} = Exams.update_exam_status(:system, exam, "finished")

      assert {:error, :exam_not_running} =
               Exams.update_exam_submission_content(submission, sample_doc("zu spät"))
    end

    test "rejects saves after the submission was submitted" do
      exam = exam_fixture(status: "running")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())
      {:ok, submitted} = Exams.submit_exam_submission(submission)

      assert {:error, :already_submitted} =
               Exams.update_exam_submission_content(submitted, sample_doc("nachträglich"))
    end
  end

  describe "submit_exam_submission/1" do
    test "marks the submission as submitted while running" do
      exam = exam_fixture(status: "running")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())

      assert {:ok, submitted} = Exams.submit_exam_submission(submission)
      assert submitted.submitted
    end

    test "rejects submission once the exam is finished" do
      exam = exam_fixture(status: "running")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())
      {:ok, _exam} = Exams.update_exam_status(:system, exam, "finished")

      assert {:error, :exam_not_running} = Exams.submit_exam_submission(submission)
    end
  end

  describe "authorization" do
    import Tasky.AccountsFixtures

    test "a foreign teacher cannot mutate an exam they don't own" do
      exam = exam_fixture()
      other = user_scope_fixture(user_fixture(%{role: "teacher"}))

      assert {:error, :unauthorized} = Exams.update_exam(other, exam, %{name: "Übernommen"})
      assert {:error, :unauthorized} = Exams.delete_exam(other, exam)
      assert {:error, :unauthorized} = Exams.open_exam_session(other, exam)
      assert {:error, :unauthorized} = Exams.save_exam_structure(other, exam, %{"type" => "doc"})
      assert {:error, :unauthorized} = Exams.update_grading_max_points(other, exam, 10.0)
    end

    test "a foreign teacher cannot grade another teacher's submission" do
      exam = exam_fixture(status: "running")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())
      other = user_scope_fixture(user_fixture(%{role: "teacher"}))

      assert {:error, :unauthorized} = Exams.set_part_points(other, submission, "q-1", 1.0)
      assert {:error, :unauthorized} = Exams.mark_part_corrected(other, submission, "q-1")
      assert {:error, :unauthorized} = Exams.set_submission_mark(other, submission, 5.0)
    end

    test "an admin can manage any teacher's exam" do
      exam = exam_fixture()
      admin = user_scope_fixture(user_fixture(%{role: "admin"}))

      assert {:ok, updated} = Exams.update_exam(admin, exam, %{name: "Admin-Bearbeitung"})
      assert updated.name == "Admin-Bearbeitung"
    end
  end

  describe "update_exam_status/3 lifecycle" do
    test "rejects transitions outside the lifecycle" do
      exam = exam_fixture()

      assert {:error, :invalid_transition} =
               Exams.update_exam_status(:system, exam, "finished")

      assert {:error, :invalid_transition} = Exams.update_exam_status(:system, exam, "draft")
    end

    test "status and enrollment_token are not mass-assignable" do
      exam = exam_fixture()

      {:ok, updated} =
        Exams.update_exam(:system, exam, %{
          "status" => "running",
          "enrollment_token" => "HACKED"
        })

      assert updated.status == "draft"
      assert updated.enrollment_token == nil
    end
  end

  describe "ExamUploadField.changeset/2" do
    alias Tasky.Exams.ExamUploadField

    test "rejects an untouched empty allowed_types default" do
      changeset = ExamUploadField.changeset(%ExamUploadField{}, %{label: "Datei"})

      refute changeset.valid?
      assert %{allowed_types: ["mindestens einen Dateityp wählen"]} = errors_on(changeset)
    end

    test "accepts a valid type selection" do
      changeset =
        ExamUploadField.changeset(%ExamUploadField{}, %{label: "Datei", allowed_types: ["pdf"]})

      assert changeset.valid?
    end
  end

  describe "duplicate guest enrollment" do
    test "the same email cannot enroll twice into one exam" do
      exam = exam_fixture(status: "open")

      assert {:ok, _} = Exams.create_exam_submission(exam, enrollment_attrs())
      assert {:error, changeset} = Exams.create_exam_submission(exam, enrollment_attrs())
      assert %{exam_id: [_message]} = errors_on(changeset)
    end
  end

  describe "generate_quit_password/0" do
    test "always produces a 6-digit numeric password" do
      for _ <- 1..100 do
        assert Exams.generate_quit_password() =~ ~r/^[1-9]\d{5}$/
      end
    end
  end
end
