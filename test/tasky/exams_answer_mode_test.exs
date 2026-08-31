defmodule Tasky.ExamsAnswerModeTest do
  @moduledoc """
  The `free_document` exam mode: chosen once on the create form, never again,
  and graded as a single synthetic part instead of per answer field.

  The two defects these tests exist for:

    * a mode that could be flipped later, stranding part-keyed grading data;
    * a duplicate silently coming back as an answer-field exam, because
      `:answer_mode` is castable on create only and `insert_exam_duplicate/3`
      is the copy's only chance to carry it over.
  """

  use Tasky.DataCase, async: false

  import Tasky.ExamsFixtures

  alias Tasky.ExamDoc
  alias Tasky.Exams
  alias Tasky.Grading

  defp teacher_scope(exam) do
    Tasky.Accounts.Scope.for_user(Tasky.Accounts.get_user!(exam.teacher_id))
  end

  defp essay_doc do
    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => "Schreibe einen Aufsatz."}]
        }
      ]
    }
  end

  describe "choosing the mode" do
    test "defaults to answer_fields" do
      exam = exam_fixture(attrs: %{name: "Ohne Modus"})

      assert exam.answer_mode == "answer_fields"
      refute Exams.free_document?(exam)
    end

    test "create persists free_document" do
      exam = exam_fixture(answer_mode: "free_document")

      assert exam.answer_mode == "free_document"
      assert Exams.free_document?(exam)
    end

    test "an unknown mode is refused" do
      scope = Tasky.AccountsFixtures.user_scope_fixture()

      assert {:error, changeset} =
               Exams.create_exam(scope, %{name: "Kaputt", answer_mode: "aufsatz"})

      assert "is invalid" in errors_on(changeset).answer_mode
    end

    test "the mode is not mass-assignable after creation" do
      exam = exam_fixture(answer_mode: "free_document")

      {:ok, updated} = Exams.update_exam(:system, exam, %{"answer_mode" => "answer_fields"})

      assert updated.answer_mode == "free_document"
    end

    test "a duplicate keeps the mode" do
      exam = exam_fixture(answer_mode: "free_document")

      {:ok, copy} = Exams.duplicate_exam(teacher_scope(exam), exam, "Kopie")

      assert copy.answer_mode == "free_document"
    end
  end

  describe "the document as one part" do
    test "the whole content is a single part, whatever it contains" do
      exam = exam_fixture(answer_mode: "free_document", attrs: %{content: essay_doc()})

      assert [part] = Exams.split_content_into_parts(exam.content, exam.answer_mode)
      assert part.id == ExamDoc.free_document_part_id()
      assert part.nodes == exam.content["content"]
    end

    test "auto-correction produces no jobs" do
      exam =
        exam_fixture(
          answer_mode: "free_document",
          status: "running",
          attrs: %{
            content: essay_doc(),
            sample_solution_points: %{ExamDoc.free_document_part_id() => 10},
            ai_correction_config: %{
              ExamDoc.free_document_part_id() => %{"auto_correct" => true}
            }
          }
        )

      submission = exam_submission_fixture(exam)
      {:ok, _} = Exams.submit_exam_submission(submission)

      assert Exams.list_bulk_correction_jobs(exam) == []
    end
  end

  describe "grading a free document" do
    setup do
      exam =
        exam_fixture(
          answer_mode: "free_document",
          status: "running",
          attrs: %{content: essay_doc()}
        )

      scope = teacher_scope(exam)
      part_id = ExamDoc.free_document_part_id()

      {:ok, exam} = Exams.set_sample_solution_part_points(scope, exam, part_id, 12)
      submission = exam_submission_fixture(exam)

      %{exam: exam, scope: scope, submission: submission, part_id: part_id}
    end

    test "points are awarded manually and clamped to the maximum", ctx do
      {:ok, submission} = Exams.set_part_points(ctx.scope, ctx.submission, ctx.part_id, 9.5)
      assert submission.points_per_part == %{ctx.part_id => 9.5}

      {:ok, submission} = Exams.set_part_points(ctx.scope, submission, ctx.part_id, 99)
      assert submission.points_per_part == %{ctx.part_id => 12.0}

      {:ok, submission} = Exams.set_part_points(ctx.scope, submission, ctx.part_id, nil)
      assert submission.points_per_part == %{}
    end

    test "the mark follows from the one part's points", ctx do
      {:ok, submission} = Exams.set_part_points(ctx.scope, ctx.submission, ctx.part_id, 6)

      max_points = Grading.sum_points(ctx.exam.sample_solution_points)
      points = Grading.sum_points(submission.points_per_part)

      assert max_points == 12.0
      assert points == 6.0
      # Half the points on the Swiss 1–6 scale: 6/12 * 5 + 1
      assert Grading.mark(points, max_points) == 3.5
    end

    test "marking the single part corrected completes the submission", ctx do
      {:ok, submission} = Exams.mark_part_corrected(ctx.scope, ctx.submission, ctx.part_id)

      assert submission.corrected_parts == [ctx.part_id]
    end
  end
end
