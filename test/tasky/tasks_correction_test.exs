defmodule Tasky.TasksCorrectionTest do
  @moduledoc """
  Die Korrektur einer Lerneinheit: das von der Lehrperson annotierte
  Antwortdokument.
  """
  use Tasky.DataCase, async: true

  alias Tasky.Tasks
  alias Tasky.Tasks.TaskSubmission

  import Tasky.AccountsFixtures, only: [user_fixture: 1, user_scope_fixture: 1]
  import Tasky.CoursesFixtures
  import Tasky.TasksFixtures

  setup do
    teacher_scope = user_scope_fixture(user_fixture(%{role: "teacher"}))
    student = user_fixture(%{role: "student"})
    student_scope = user_scope_fixture(student)

    course = course_fixture(scope: teacher_scope)
    {:ok, _} = Tasky.Courses.enroll_student(course.id, student.id)

    task = task_fixture(teacher_scope, %{status: "published", course_id: course.id})
    {:ok, submission} = Tasks.get_or_create_submission(student_scope, task.id)

    %{
      teacher_scope: teacher_scope,
      student_scope: student_scope,
      task: task,
      submission: submission
    }
  end

  defp doc(text) do
    %{
      "type" => "doc",
      "content" => [
        %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}
      ]
    }
  end

  describe "correction_content/1" do
    test "fällt auf die Antworten zurück, solange nichts korrigiert ist" do
      assert Tasks.correction_content(%TaskSubmission{content: %{"a" => 1}}) == %{"a" => 1}
      assert Tasks.correction_content(%TaskSubmission{content: nil}) == %{}
    end

    test "bevorzugt die Korrektur, sobald es eine gibt" do
      submission = %TaskSubmission{content: %{"a" => 1}, corrected_content: %{"b" => 2}}
      assert Tasks.correction_content(submission) == %{"b" => 2}
    end
  end

  describe "save_correction_content/4" do
    test "speichert nur an einer eingereichten Abgabe", %{
      teacher_scope: scope,
      task: task,
      submission: submission,
      student_scope: student_scope
    } do
      assert {:error, :not_reviewable} =
               Tasks.save_correction_content(scope, task, submission.id, doc("Anmerkung"))

      {:ok, _} = Tasks.complete_task(student_scope, submission.id)

      assert {:ok, updated} =
               Tasks.save_correction_content(scope, task, submission.id, doc("Anmerkung"))

      assert Tasks.has_correction?(updated)
      assert Tasks.correction_content(updated) == doc("Anmerkung")
    end

    test "weist eine fremde Lehrperson ab", %{
      task: task,
      submission: submission,
      student_scope: student_scope
    } do
      {:ok, _} = Tasks.complete_task(student_scope, submission.id)
      other = user_scope_fixture(user_fixture(%{role: "teacher"}))

      assert {:error, :unauthorized} =
               Tasks.save_correction_content(other, task, submission.id, doc("x"))
    end

    test "meldet eine unbekannte Abgabe", %{teacher_scope: scope, task: task} do
      assert {:error, :not_found} =
               Tasks.save_correction_content(scope, task, -1, doc("x"))
    end

    test "lehnt ein zu grosses Dokument ab", %{
      teacher_scope: scope,
      task: task,
      submission: submission,
      student_scope: student_scope
    } do
      {:ok, _} = Tasks.complete_task(student_scope, submission.id)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Tasks.save_correction_content(
                 scope,
                 task,
                 submission.id,
                 doc(String.duplicate("x", 6_000_000))
               )

      assert "Inhalt ist zu gross" in errors_on(changeset).corrected_content
    end
  end

  describe "answer_doc_for_student/2" do
    setup %{teacher_scope: scope, task: task, submission: submission, student_scope: student} do
      {:ok, _} = Tasks.save_student_answers(student, submission, doc("Meine Antwort"))
      {:ok, submission} = Tasks.complete_task(student, submission.id)
      {:ok, task} = Tasks.set_solution_release_mode(scope, task, "manual")

      %{task: task, submission: submission}
    end

    test "gibt ohne Korrektur die eigenen Antworten", %{task: task, submission: submission} do
      assert {:own, %{"content" => _}} = Tasks.answer_doc_for_student(task, submission)
    end

    test "gibt die Korrektur erst nach der Freigabe", %{
      teacher_scope: scope,
      task: task,
      submission: submission
    } do
      {:ok, _} = Tasks.save_correction_content(scope, task, submission.id, doc("Korrigiert"))
      submission = Repo.reload!(submission)

      assert {:own, _} = Tasks.answer_doc_for_student(task, submission)

      {:ok, released} = Tasks.release_solution(scope, task, submission.id)
      assert {:corrected, corrected} = Tasks.answer_doc_for_student(task, released)
      assert corrected == doc("Korrigiert")
    end
  end

  describe "Wiedereinreichen" do
    test "räumt die Korrektur weg, behält aber die Freigabe", %{
      teacher_scope: scope,
      task: task,
      submission: submission,
      student_scope: student_scope
    } do
      {:ok, task} = Tasks.set_solution_release_mode(scope, task, "manual")
      {:ok, _} = Tasks.complete_task(student_scope, submission.id)
      {:ok, _} = Tasks.save_correction_content(scope, task, submission.id, doc("Anmerkung"))
      {:ok, released} = Tasks.release_solution(scope, task, submission.id)
      stamp = released.solution_released_at

      {:ok, _} = Tasks.review_submission(scope, submission.id, "review_denied", %{})
      {:ok, resubmitted} = Tasks.complete_task(student_scope, submission.id)

      refute Tasks.has_correction?(resubmitted)
      assert resubmitted.solution_released_at == stamp
      assert Tasks.solution_visible?(task, resubmitted)
    end
  end
end
