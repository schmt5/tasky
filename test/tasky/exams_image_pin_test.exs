defmodule Tasky.ExamsImagePinTest do
  @moduledoc """
  Pin auf Bild in einer Prüfung: Wie viele Pins es gibt und wo sie hingehören,
  legt die Musterlösung fest; Lernende bekommen nur die Pin-ids, und das Bild
  wird als ein Block bewertet.
  """
  use Tasky.DataCase, async: false

  import Tasky.AccountsFixtures

  alias Tasky.AI.NodePatcher
  alias Tasky.Correction.StringComparator
  alias Tasky.Exams

  defp text(t), do: %{"type" => "text", "text" => t}

  defp doc(pins) do
    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "heading",
          "attrs" => %{"level" => 3, "partId" => "q-1"},
          "content" => [text("Wo liegen Bern und Genf?")]
        },
        %{
          "type" => "imagePin",
          "attrs" => %{
            "answerId" => "map",
            "src" => "/uploads/map.png",
            "aspect" => 1.5,
            "pins" => pins
          }
        }
      ]
    }
  end

  @solution [
    %{"pinId" => "bern", "x" => 0.4, "y" => 0.3, "zone" => %{"shape" => "circle", "r" => 0.05}},
    %{
      "pinId" => "genf",
      "x" => 0.1,
      "y" => 0.8,
      "zone" => %{"shape" => "rect", "w" => 0.1, "h" => 0.1}
    }
  ]

  defp part_nodes(doc),
    do: doc |> Exams.split_content_into_parts("answer_fields") |> hd() |> Map.fetch!(:nodes)

  defp setup_exam do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)

    {:ok, exam} =
      Tasky.ExamsFixtures.create_exam_with_document(scope, %{
        name: "Karte",
        content: doc([]),
        sample_solution_points: %{"q-1" => 2}
      })

    # A part of only pins is always auto-corrected, so saving the solution
    # starts a run — let it finish before the test's sandbox goes away.
    Exams.subscribe_correction(exam.id)
    {:ok, exam} = Exams.save_sample_solution_part(scope, exam, "q-1", part_nodes(doc(@solution)))
    assert_receive {:bulk_correction_done, _}, 2_000

    %{scope: scope, exam: exam}
  end

  test "the sample solution holds the pins; the content only their ids" do
    %{exam: exam} = setup_exam()

    assert exam.sample_solution == %{"map" => @solution}

    assert [_heading, %{"attrs" => %{"pins" => [%{"pinId" => "bern"}, %{"pinId" => "genf"}]}}] =
             exam.content["content"]
  end

  test "a save from the content tab without pins does not take them away" do
    %{scope: scope, exam: exam} = setup_exam()

    {:ok, exam} = Exams.save_exam_structure(scope, exam, doc([]))
    assert_receive {:bulk_correction_done, _}, 2_000

    assert [_heading, %{"attrs" => %{"pins" => [%{"pinId" => "bern"}, %{"pinId" => "genf"}]}}] =
             exam.content["content"]

    assert exam.sample_solution == %{"map" => @solution}
  end

  test "a part of only pins is auto-corrected" do
    %{exam: exam} = setup_exam()
    assert MapSet.member?(Exams.auto_correct_part_ids(exam), "q-1")
  end

  test "a learner's pins are saved and graded as one block, partly right in shares" do
    %{exam: exam} = setup_exam()
    {:ok, exam} = Exams.open_exam_session(:system, exam, "anonymous")
    {:ok, exam} = Exams.update_exam_status(:system, exam, "running")

    {:ok, submission} =
      Exams.create_exam_submission(exam, %{
        "firstname" => "Anna",
        "lastname" => "Test",
        "email" => "anna@example.com"
      })

    {:ok, submission} =
      Exams.save_exam_submission_answers(submission, %{
        "answers" => %{"map" => [%{"pinId" => "bern", "x" => 0.41, "y" => 0.31}]}
      })

    assert [_heading, %{"attrs" => %{"pins" => pins}}] = submission.content["content"]

    assert pins == [
             %{"pinId" => "bern", "x" => 0.41, "y" => 0.31},
             %{"pinId" => "genf", "x" => nil, "y" => nil}
           ]

    nodes = part_nodes(Exams.correction_content(submission))
    {annotated, _count} = NodePatcher.annotate(nodes)
    blocks = NodePatcher.list_answer_blocks(nodes)

    assert {:ok, %{verdicts: %{"1" => 1.0}}} =
             StringComparator.correct_part(
               annotated,
               part_nodes(Exams.sample_solution_doc(exam)),
               2,
               %{block_points: Exams.resolve_block_points(exam, "q-1", blocks)}
             )
  end

  test "the learner's process never holds a pin's position" do
    %{exam: exam} = setup_exam()
    learner_exam = Exams.learner_exam(exam)

    refute inspect(learner_exam) =~ "zone"
    refute inspect(learner_exam) =~ "0.4"
  end

  test "the zones the correction view draws are never stored with the answer" do
    %{scope: scope, exam: exam} = setup_exam()
    {:ok, exam} = Exams.open_exam_session(:system, exam, "anonymous")
    {:ok, exam} = Exams.update_exam_status(:system, exam, "running")

    {:ok, submission} =
      Exams.create_exam_submission(exam, %{
        "firstname" => "Ben",
        "lastname" => "Test",
        "email" => "ben@example.com"
      })

    {:ok, submission} =
      Exams.save_exam_submission_answers(submission, %{
        "answers" => %{"map" => [%{"pinId" => "bern", "x" => 0.5, "y" => 0.5}]}
      })

    nodes =
      submission
      |> Exams.correction_content()
      |> part_nodes()
      |> Tasky.Correction.ImagePin.with_solution(exam.sample_solution)

    assert inspect(nodes) =~ "zone"

    {:ok, updated} = Exams.update_corrected_part_content(scope, submission, "q-1", nodes)

    refute inspect(updated.corrected_content) =~ "zone"
  end
end
