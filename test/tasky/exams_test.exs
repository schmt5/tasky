defmodule Tasky.ExamsTest do
  use Tasky.DataCase, async: false

  import Tasky.AccountsFixtures

  alias Tasky.Exams

  defp exam_fixture(status) do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)

    {:ok, exam} =
      Exams.create_exam(scope, %{
        name: "Test Prüfung",
        content: %{"type" => "doc", "content" => []}
      })

    case status do
      "draft" ->
        exam

      "open" ->
        {:ok, exam} = Exams.open_exam_session(exam)
        exam

      other ->
        {:ok, exam} = Exams.open_exam_session(exam)
        {:ok, exam} = Exams.update_exam_status(exam, other)
        exam
    end
  end

  defp enrollment_attrs, do: %{"firstname" => "Max", "lastname" => "Muster"}

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
      exam = exam_fixture("open")

      assert {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())
      assert submission.firstname == "Max"
      assert submission.exam_token
      refute submission.submitted
    end

    test "enrolls when the exam is already running" do
      exam = exam_fixture("running")

      assert {:ok, _submission} = Exams.create_exam_submission(exam, enrollment_attrs())
    end

    test "rejects enrollment for draft and finished exams" do
      assert {:error, :exam_not_open} =
               Exams.create_exam_submission(exam_fixture("draft"), enrollment_attrs())

      assert {:error, :exam_not_open} =
               Exams.create_exam_submission(exam_fixture("finished"), enrollment_attrs())
    end
  end

  describe "update_exam_submission_content/2" do
    test "saves content while the exam is running" do
      exam = exam_fixture("running")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())

      doc = sample_doc("Meine Antwort")
      assert {:ok, updated} = Exams.update_exam_submission_content(submission, doc)
      assert updated.content == doc
    end

    test "rejects saves once the exam is finished" do
      exam = exam_fixture("running")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())
      {:ok, _exam} = Exams.update_exam_status(exam, "finished")

      assert {:error, :exam_not_running} =
               Exams.update_exam_submission_content(submission, sample_doc("zu spät"))
    end

    test "rejects saves after the submission was submitted" do
      exam = exam_fixture("running")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())
      {:ok, submitted} = Exams.submit_exam_submission(submission)

      assert {:error, :already_submitted} =
               Exams.update_exam_submission_content(submitted, sample_doc("nachträglich"))
    end
  end

  describe "submit_exam_submission/1" do
    test "marks the submission as submitted while running" do
      exam = exam_fixture("running")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())

      assert {:ok, submitted} = Exams.submit_exam_submission(submission)
      assert submitted.submitted
    end

    test "rejects submission once the exam is finished" do
      exam = exam_fixture("running")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())
      {:ok, _exam} = Exams.update_exam_status(exam, "finished")

      assert {:error, :exam_not_running} = Exams.submit_exam_submission(submission)
    end
  end
end
