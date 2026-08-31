defmodule Tasky.ExamsAutoCorrectionTest do
  @moduledoc """
  `Exams.apply_auto_correction/5` and the verdict vocabulary around it had no
  test coverage at all, which is how two defects survived: the string comparator
  wrote `"incorrect"`, a value nothing downstream understands, and a re-run
  overwrote verdicts the teacher had entered by hand.
  """
  use Tasky.DataCase, async: false

  import Tasky.AccountsFixtures

  alias Tasky.AI.NodePatcher
  alias Tasky.Correction.StringComparator
  alias Tasky.Exams

  defp exam_fixture(attrs) do
    scope = user_scope_fixture(user_fixture(%{role: "teacher"}))

    {:ok, exam} =
      Exams.create_exam(scope, Map.merge(%{name: "Test Prüfung", content: question_doc()}, attrs))

    exam
  end

  defp question_doc(block_ids \\ ["a1", "a2"]) do
    %{
      "type" => "doc",
      "content" =>
        [
          %{
            "type" => "heading",
            "attrs" => %{"level" => 3, "partId" => "q-1"},
            "content" => [%{"type" => "text", "text" => "Frage 1"}]
          }
        ] ++ Enum.map(block_ids, &answer_block(&1, "Antwort #{&1}"))
    }
  end

  defp answer_block(id, text) do
    %{
      "type" => "answerBlock",
      "attrs" => %{"answerId" => id},
      "content" => [
        %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}
      ]
    }
  end

  defp submission_fixture(exam) do
    exam = Repo.get!(Tasky.Exams.Exam, exam.id)

    exam =
      if exam.status == "running" do
        exam
      else
        {:ok, exam} = Exams.open_exam_session(:system, exam, "anonymous")
        {:ok, exam} = Exams.update_exam_status(:system, exam, "running")
        exam
      end

    {:ok, submission} =
      Exams.create_exam_submission(exam, %{
        "firstname" => "Max",
        "lastname" => "Muster",
        "email" => "max@example.com"
      })

    {:ok, submission} = Exams.update_exam_submission_content(submission, question_doc())
    submission
  end

  defp part_nodes(submission) do
    submission
    |> Exams.correction_content()
    |> Exams.split_content_into_parts("answer_fields")
    |> Enum.find(&(&1.id == "q-1"))
    |> Map.fetch!(:nodes)
  end

  describe "verdict vocabulary" do
    test "the comparator speaks the same vocabulary as block_verdicts" do
      # `"incorrect"` was rejected by `set_block_verdict/5`'s own guard, ignored
      # by `Grading.awarded_points/2`'s named clauses and mapped to no marker —
      # so an auto-wrong block rendered as ungraded and lost its ❌.
      {annotated, _count} = NodePatcher.annotate([answer_block("a1", "falsch")])

      {:ok, %{verdicts: verdicts}} =
        StringComparator.correct_part(annotated, [answer_block("a1", "richtig")], 2)

      assert Map.values(verdicts) == ["wrong"]

      for verdict <- Map.values(verdicts) do
        assert verdict in ["correct", "half", "wrong"]
        assert NodePatcher.rewrite_markers([answer_block("a1", "x")], %{0 => verdict}) != []
      end
    end

    test "a wrong verdict awards zero and renders the ❌ marker" do
      assert Tasky.Grading.awarded_points("wrong", 2) == 0

      [node] = NodePatcher.rewrite_markers([answer_block("a1", "falsch")], %{0 => "wrong"})
      assert inspect(node) =~ "❌"
    end
  end

  describe "apply_auto_correction/5" do
    test "writes verdicts, points and the auto flag" do
      exam = exam_fixture(%{sample_solution_points: %{"q-1" => 2}})
      submission = submission_fixture(exam)

      {:ok, updated} =
        Exams.apply_auto_correction(:system, submission, "q-1", part_nodes(submission),
          verdicts: %{"a1" => "correct", "a2" => "wrong"}
        )

      assert updated.block_verdicts["a1"] == "correct"
      assert updated.block_verdicts["a2"] == "wrong"
      assert updated.points_per_part["q-1"] == 1
      assert "q-1" in updated.auto_corrected_parts
    end

    test "a re-run refreshes its own previous verdicts" do
      exam = exam_fixture(%{sample_solution_points: %{"q-1" => 2}})
      submission = submission_fixture(exam)

      {:ok, updated} =
        Exams.apply_auto_correction(:system, submission, "q-1", part_nodes(submission),
          verdicts: %{"a1" => "wrong"}
        )

      {:ok, updated} =
        Exams.apply_auto_correction(:system, updated, "q-1", part_nodes(updated),
          verdicts: %{"a1" => "correct"}
        )

      assert updated.block_verdicts["a1"] == "correct"
    end

    test "a re-run does not overwrite a verdict the teacher set by hand" do
      # The teacher hand-grades a block but has not clicked "Teil korrigiert"
      # yet, so the part is still eligible for auto-correction. Editing any
      # model answer re-runs it; the machine used to win the merge.
      exam = exam_fixture(%{sample_solution_points: %{"q-1" => 2}})
      submission = submission_fixture(exam)

      {:ok, submission} =
        Exams.apply_auto_correction(:system, submission, "q-1", part_nodes(submission),
          verdicts: %{"a1" => "wrong", "a2" => "wrong"}
        )

      # Teacher overrides block a1 (index 0).
      {:ok, submission} = Exams.set_block_verdict(:system, submission, "q-1", 0, "correct")
      assert submission.block_verdicts["a1"] == "correct"
      teacher_points = submission.points_per_part["q-1"]

      {:ok, rerun} =
        Exams.apply_auto_correction(:system, submission, "q-1", part_nodes(submission),
          verdicts: %{"a1" => "wrong", "a2" => "wrong"}
        )

      assert rerun.block_verdicts["a1"] == "correct",
             "the teacher's verdict must survive a re-run"

      assert rerun.block_verdicts["a2"] == "wrong"
      assert rerun.points_per_part["q-1"] == teacher_points
    end

    test "a re-run that changes an unjudged block also updates the part total" do
      # The regression this file's other re-run tests could not see: they re-run
      # with the non-manual block unchanged, so a frozen total happens to be
      # right. Once any block is hand-graded, the total used to be carried over
      # verbatim while the *other* blocks' verdicts and ✅/❌ markers were still
      # refreshed — so points, verdicts and the document disagreed until the
      # teacher happened to touch that part again.
      exam = exam_fixture(%{sample_solution_points: %{"q-1" => 2}})
      submission = submission_fixture(exam)

      {:ok, submission} =
        Exams.apply_auto_correction(:system, submission, "q-1", part_nodes(submission),
          verdicts: %{"a1" => "wrong", "a2" => "wrong"}
        )

      assert submission.points_per_part["q-1"] == 0

      # Teacher overrides a1 (index 0); a1 counts as manual from here on.
      {:ok, submission} = Exams.set_block_verdict(:system, submission, "q-1", 0, "correct")
      assert submission.points_per_part["q-1"] == 1

      # Model answer edited, re-run: a1 stays the teacher's, a2 flips to correct.
      {:ok, rerun} =
        Exams.apply_auto_correction(:system, submission, "q-1", part_nodes(submission),
          verdicts: %{"a1" => "wrong", "a2" => "correct"}
        )

      assert rerun.block_verdicts == %{"a1" => "correct", "a2" => "correct"}

      assert rerun.points_per_part["q-1"] == 2,
             "the part total must follow the verdicts that were actually stored"

      # And the document must agree with both.
      [first, second] = NodePatcher.list_answer_blocks(part_nodes(rerun))
      assert first.inferred_verdict == "correct"
      assert second.inferred_verdict == "correct"
    end

    test "markers follow the stored verdicts, not the runner's own" do
      exam = exam_fixture(%{sample_solution_points: %{"q-1" => 2}})
      submission = submission_fixture(exam)

      {:ok, submission} =
        Exams.apply_auto_correction(:system, submission, "q-1", part_nodes(submission),
          verdicts: %{"a1" => "wrong", "a2" => "wrong"}
        )

      {:ok, submission} = Exams.set_block_verdict(:system, submission, "q-1", 0, "correct")

      {:ok, rerun} =
        Exams.apply_auto_correction(:system, submission, "q-1", part_nodes(submission),
          verdicts: %{"a1" => "wrong", "a2" => "wrong"}
        )

      # `list_answer_blocks/1` strips the markers out of `text` and reports what
      # they said in `inferred_verdict`, which is what the viewers read back.
      [first, second] = NodePatcher.list_answer_blocks(part_nodes(rerun))
      assert first.inferred_verdict == "correct"
      assert second.inferred_verdict == "wrong"
    end

    test "an unknown part is rejected" do
      exam = exam_fixture(%{sample_solution_points: %{"q-1" => 2}})
      submission = submission_fixture(exam)

      assert {:error, :unknown_part} =
               Exams.apply_auto_correction(:system, submission, "q-99", [], verdicts: %{})
    end
  end
end
