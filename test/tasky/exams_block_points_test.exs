defmodule Tasky.ExamsBlockPointsTest do
  use Tasky.DataCase, async: false

  import Tasky.AccountsFixtures

  alias Tasky.AI.NodePatcher
  alias Tasky.Exams

  defp exam_fixture(attrs \\ %{}) do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)

    {:ok, exam} =
      Exams.create_exam(
        scope,
        Map.merge(%{name: "Test Prüfung", content: question_doc()}, attrs)
      )

    exam
  end

  defp question_doc(block_ids \\ [11, 22, 33, 44]) do
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

  defp submission_fixture(exam, attrs \\ %{}) do
    # Refetch: callers may hold a stale struct after earlier fixture calls.
    exam = Tasky.Repo.get!(Tasky.Exams.Exam, exam.id)

    exam =
      if exam.status == "running" do
        exam
      else
        {:ok, exam} = Exams.open_exam_session(:system, exam, "anonymous")
        {:ok, exam} = Exams.update_exam_status(:system, exam, "running")
        exam
      end

    {:ok, submission} =
      Exams.create_exam_submission(
        exam,
        Map.merge(
          %{
            "firstname" => "Max",
            "lastname" => "Muster",
            "email" => "max@example.com"
          },
          attrs
        )
      )

    {:ok, submission} = Exams.update_exam_submission_content(submission, exam.content)
    submission
  end

  defp blocks_of(exam, part_id) do
    (exam.content || %{})
    |> Exams.split_content_into_parts(exam.answer_mode)
    |> Enum.find(&(&1.id == part_id))
    |> Map.fetch!(:nodes)
    |> NodePatcher.list_answer_blocks()
  end

  describe "resolve_block_points/3" do
    test "splits max points equally when no custom distribution exists" do
      exam = exam_fixture(%{sample_solution_points: %{"q-1" => 4}})
      blocks = blocks_of(exam, "q-1")

      assert %{0 => 1.0, 1 => 1.0, 2 => 1.0, 3 => 1.0} =
               Exams.resolve_block_points(exam, "q-1", blocks)
    end

    test "uses the custom per-answer-id values, unknown ids count 0" do
      exam =
        exam_fixture(%{
          sample_solution_points: %{"q-1" => 4},
          sample_solution_block_points: %{
            "q-1" => %{"11" => 1.5, "22" => 1.5, "33" => 0.5}
            # "44" deliberately missing
          }
        })

      blocks = blocks_of(exam, "q-1")

      assert %{0 => 1.5, 1 => 1.5, 2 => 0.5, 3 => 0} =
               Exams.resolve_block_points(exam, "q-1", blocks)
    end

    test "returns nil without configured points or without blocks" do
      exam = exam_fixture()
      blocks = blocks_of(exam, "q-1")

      assert Exams.resolve_block_points(exam, "q-1", blocks) == nil
      assert Exams.resolve_block_points(exam, "q-1", []) == nil
    end
  end

  describe "set_block_verdict/4 with per-block points" do
    test "string verdicts sum each block's own points" do
      exam =
        exam_fixture(%{
          sample_solution_points: %{"q-1" => 4},
          sample_solution_block_points: %{
            "q-1" => %{"11" => 1.5, "22" => 1.5, "33" => 0.5, "44" => 0.5}
          }
        })

      submission = submission_fixture(exam)

      {:ok, submission} = Exams.set_block_verdict(:system, submission, "q-1", 0, "correct")
      {:ok, submission} = Exams.set_block_verdict(:system, submission, "q-1", 1, "wrong")
      {:ok, submission} = Exams.set_block_verdict(:system, submission, "q-1", 2, "correct")

      assert submission.points_per_part["q-1"] == 2
    end

    test "verdict writes based on a stale struct don't lose earlier verdicts" do
      exam = exam_fixture(%{sample_solution_points: %{"q-1" => 4}})
      submission = submission_fixture(exam)

      # Both writes go through the SAME stale struct — the in-transaction
      # refetch must merge them instead of the second clobbering the first.
      {:ok, _} = Exams.set_block_verdict(:system, submission, "q-1", 0, "correct")
      {:ok, _} = Exams.set_block_verdict(:system, submission, "q-1", 1, "wrong")

      reloaded = Tasky.Repo.get!(Tasky.Exams.ExamSubmission, submission.id)
      assert reloaded.block_verdicts["11"] == "correct"
      assert reloaded.block_verdicts["22"] == "wrong"
    end

    test "set_block_verdict_bulk sets the same verdict across submissions" do
      exam = exam_fixture(%{sample_solution_points: %{"q-1" => 4}})
      sub_a = submission_fixture(exam)
      sub_b = submission_fixture(exam, %{"email" => "zwei@example.com"})

      {:ok, updated} =
        Exams.set_block_verdict_bulk(:system, exam, "q-1", 0, "correct", [sub_a.id, sub_b.id])

      assert length(updated) == 2
      assert Enum.all?(updated, &(&1.block_verdicts["11"] == "correct"))
    end

    test "numeric verdicts are clamped to the block max and rounded to 0.25" do
      exam =
        exam_fixture(%{
          sample_solution_points: %{"q-1" => 4},
          sample_solution_block_points: %{
            "q-1" => %{"11" => 1.5, "22" => 1.5, "33" => 0.5, "44" => 0.5}
          }
        })

      submission = submission_fixture(exam)

      # 99 clamps to 1.5; 0.3 rounds to 0.25; -2 clamps to 0
      {:ok, submission} = Exams.set_block_verdict(:system, submission, "q-1", 0, 99)
      {:ok, submission} = Exams.set_block_verdict(:system, submission, "q-1", 1, 0.3)
      {:ok, submission} = Exams.set_block_verdict(:system, submission, "q-1", 2, -2)

      assert submission.block_verdicts["11"] == 1.5
      assert submission.block_verdicts["22"] == 0.25
      assert submission.block_verdicts["33"] == 0.0
      assert submission.points_per_part["q-1"] == 1.75
    end

    test "numeric verdicts map to the matching ✅/🟡/❌ markers" do
      exam = exam_fixture(%{sample_solution_points: %{"q-1" => 4}})
      submission = submission_fixture(exam)

      # equal split → 1.0 per block
      {:ok, submission} = Exams.set_block_verdict(:system, submission, "q-1", 0, 1.0)
      {:ok, submission} = Exams.set_block_verdict(:system, submission, "q-1", 1, 0.5)
      {:ok, submission} = Exams.set_block_verdict(:system, submission, "q-1", 2, 0)

      inferred =
        submission.corrected_content
        |> Exams.split_content_into_parts("answer_fields")
        |> Enum.find(&(&1.id == "q-1"))
        |> Map.fetch!(:nodes)
        |> NodePatcher.list_answer_blocks()
        |> Map.new(&{&1.index, &1.inferred_verdict})

      assert inferred[0] == "correct"
      assert inferred[1] == "half"
      assert inferred[2] == "wrong"
    end

    test "legacy half verdict still counts half the block points" do
      exam = exam_fixture(%{sample_solution_points: %{"q-1" => 4}})
      submission = submission_fixture(exam)

      {:ok, submission} = Exams.set_block_verdict(:system, submission, "q-1", 0, "half")

      assert submission.points_per_part["q-1"] == 0.5
    end
  end

  describe "custom block point setters" do
    test "enable_custom_block_points seeds equal shares and keeps the total" do
      exam = exam_fixture(%{sample_solution_points: %{"q-1" => 4}})

      {:ok, exam} = Exams.enable_custom_block_points(:system, exam, "q-1")

      assert exam.sample_solution_block_points["q-1"] ==
               %{"11" => 1, "22" => 1, "33" => 1, "44" => 1}

      assert exam.sample_solution_points["q-1"] == 4
      assert Exams.custom_block_points?(exam, "q-1")
    end

    test "set_sample_solution_block_point keeps the part total in sync as the sum" do
      exam = exam_fixture(%{sample_solution_points: %{"q-1" => 4}})
      {:ok, exam} = Exams.enable_custom_block_points(:system, exam, "q-1")

      {:ok, exam} = Exams.set_sample_solution_block_point(:system, exam, "q-1", "11", 1.5)
      {:ok, exam} = Exams.set_sample_solution_block_point(:system, exam, "q-1", "22", 1.5)
      {:ok, exam} = Exams.set_sample_solution_block_point(:system, exam, "q-1", "33", 0.5)
      {:ok, exam} = Exams.set_sample_solution_block_point(:system, exam, "q-1", "44", 0.5)

      assert exam.sample_solution_points["q-1"] == 4
      assert exam.sample_solution_block_points["q-1"]["33"] == 0.5
    end

    test "clear_custom_block_points falls back to equal split, total preserved" do
      exam = exam_fixture(%{sample_solution_points: %{"q-1" => 4}})
      {:ok, exam} = Exams.enable_custom_block_points(:system, exam, "q-1")
      {:ok, exam} = Exams.set_sample_solution_block_point(:system, exam, "q-1", "11", 3)

      {:ok, exam} = Exams.clear_custom_block_points(:system, exam, "q-1")

      refute Exams.custom_block_points?(exam, "q-1")
      # last sum stays as the part total
      assert exam.sample_solution_points["q-1"] == 6
    end
  end

  describe "pruning on structure edits" do
    test "removing a block drops its custom points and shrinks the total" do
      exam =
        exam_fixture(%{
          sample_solution_points: %{"q-1" => 4},
          sample_solution_block_points: %{
            "q-1" => %{"11" => 1.5, "22" => 1.5, "33" => 0.5, "44" => 0.5}
          }
        })

      # New structure without block 44
      {:ok, exam} = Exams.save_exam_structure(:system, exam, question_doc([11, 22, 33]))

      assert exam.sample_solution_block_points["q-1"] ==
               %{"11" => 1.5, "22" => 1.5, "33" => 0.5}

      assert exam.sample_solution_points["q-1"] == 3.5
    end

    test "removing all blocks of a custom part drops the entry but keeps the total" do
      exam =
        exam_fixture(%{
          sample_solution_points: %{"q-1" => 4},
          sample_solution_block_points: %{"q-1" => %{"11" => 4}}
        })

      {:ok, exam} = Exams.save_exam_structure(:system, exam, question_doc([99]))

      refute Map.has_key?(exam.sample_solution_block_points, "q-1")
      assert exam.sample_solution_points["q-1"] == 4
    end

    test "deleting a whole question drops its points from the exam total" do
      # The bug this pins: `sample_solution_points` was never pruned by part id,
      # so a deleted question kept inflating the grading denominator — silently
      # depressing every student's mark on screen and in the PDF.
      exam =
        exam_fixture(%{
          sample_solution_points: %{"q-1" => 6, "q-2" => 4}
        })

      {:ok, exam} = Exams.save_exam_structure(:system, exam, question_doc())

      assert Map.keys(exam.sample_solution_points) == ["q-1"]
      assert Tasky.Grading.sum_points(exam.sample_solution_points) == 6
    end

    test "deleting a question also drops its custom block points" do
      exam =
        exam_fixture(%{
          sample_solution_points: %{"q-1" => 6, "q-2" => 4},
          sample_solution_block_points: %{"q-2" => %{"77" => 4}}
        })

      {:ok, exam} = Exams.save_exam_structure(:system, exam, question_doc())

      refute Map.has_key?(exam.sample_solution_block_points, "q-2")
      refute Map.has_key?(exam.sample_solution_points, "q-2")
    end
  end

  describe "enable/clear custom block points round trip" do
    test "enabling then clearing leaves the part total untouched" do
      # Rounding each equal share independently (2 / 3 → 3 × 0.75 = 2.25) and
      # then setting the total to that sum let a no-op UI round trip ratchet the
      # exam's max points up by 0.25 every time.
      exam =
        exam_fixture(%{
          content: question_doc([11, 22, 33]),
          sample_solution_points: %{"q-1" => 2}
        })

      {:ok, exam} = Exams.enable_custom_block_points(:system, exam, "q-1")
      assert exam.sample_solution_points["q-1"] == 2

      {:ok, exam} = Exams.clear_custom_block_points(:system, exam, "q-1")
      assert exam.sample_solution_points["q-1"] == 2

      # And again, to prove it does not creep across repeated toggles.
      {:ok, exam} = Exams.enable_custom_block_points(:system, exam, "q-1")
      {:ok, exam} = Exams.clear_custom_block_points(:system, exam, "q-1")
      assert exam.sample_solution_points["q-1"] == 2
    end

    test "seeded shares sum to exactly the part total" do
      exam =
        exam_fixture(%{
          content: question_doc([11, 22, 33]),
          sample_solution_points: %{"q-1" => 2}
        })

      {:ok, exam} = Exams.enable_custom_block_points(:system, exam, "q-1")

      shares = exam.sample_solution_block_points["q-1"]
      assert shares |> Map.values() |> Enum.sum() == 2
      # Every share stays on the 0.25 grid.
      assert Enum.all?(Map.values(shares), &(&1 * 4 == trunc(&1 * 4)))
    end
  end

  describe "list_part_answer_groups/2 block max points" do
    test "exposes each block's resolved max points" do
      exam =
        exam_fixture(%{
          sample_solution_points: %{"q-1" => 4},
          sample_solution_block_points: %{
            "q-1" => %{"11" => 1.5, "22" => 1.5, "33" => 0.5, "44" => 0.5}
          }
        })

      _submission = submission_fixture(exam)

      blocks = Exams.list_part_answer_groups(exam, "q-1")

      assert Enum.map(blocks, & &1.max_points) == [1.5, 1.5, 0.5, 0.5]
    end
  end

  describe "set_part_points/4 validation" do
    setup do
      exam = exam_fixture(%{sample_solution_points: %{"q-1" => 4}})
      %{exam: exam, submission: submission_fixture(exam)}
    end

    test "clamps to the part's max points", %{submission: submission} do
      # `step`/`max` on the number input are client-side only; a crafted event
      # used to store the raw value straight into the exam total.
      {:ok, updated} = Exams.set_part_points(:system, submission, "q-1", 1000)
      assert updated.points_per_part["q-1"] == 4
    end

    test "rejects negative points", %{submission: submission} do
      {:ok, updated} = Exams.set_part_points(:system, submission, "q-1", -5)
      assert updated.points_per_part["q-1"] == 0
    end

    test "quarter-rounds the stored value", %{submission: submission} do
      {:ok, updated} = Exams.set_part_points(:system, submission, "q-1", 1.3)
      assert updated.points_per_part["q-1"] == 1.25
    end

    test "nil still clears the entry", %{submission: submission} do
      {:ok, updated} = Exams.set_part_points(:system, submission, "q-1", 2)
      assert updated.points_per_part["q-1"] == 2

      {:ok, updated} = Exams.set_part_points(:system, updated, "q-1", nil)
      refute Map.has_key?(updated.points_per_part, "q-1")
    end
  end
end
