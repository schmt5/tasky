defmodule TaskyWeb.ExamSubmissionPdfTest do
  use Tasky.DataCase, async: true

  import Tasky.ExamsFixtures

  alias Tasky.Exams.ExamSubmission
  alias TaskyWeb.ExamSubmissionPdf

  defp answer_doc(answer) do
    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "heading",
          "attrs" => %{"level" => 3, "partId" => "q-1"},
          "content" => [%{"type" => "text", "text" => "Frage 1"}]
        },
        %{
          "type" => "answerBlock",
          "attrs" => %{"answerId" => "a"},
          "content" => [
            %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => answer}]}
          ]
        }
      ]
    }
  end

  defp submission do
    %ExamSubmission{
      id: 7,
      firstname: "Anna",
      lastname: "Muster",
      content: answer_doc("Meine Antwort"),
      corrected_content: answer_doc("Korrigiert"),
      points_per_part: %{"q-1" => 2.5}
    }
  end

  defp exam do
    exam_fixture(attrs: %{content: answer_doc("")})
    |> Map.merge(%{sample_solution_points: %{"q-1" => 4}, mark_step: "0.25"})
  end

  describe "data/3" do
    test "carries name, points and mark from grading_result/2" do
      data = ExamSubmissionPdf.data(exam(), submission(), %{show_points_and_mark: true})

      assert data["student_name"] == "Anna Muster"
      assert data["show_points_and_mark"]
      assert data["points"] == "2.5"
      assert data["max_points"] == "4"
      assert is_binary(data["mark"])
    end

    test "shows the corrected answers only when the correction is selected" do
      plain = ExamSubmissionPdf.data(exam(), submission(), %{show_correction: false})
      corrected = ExamSubmissionPdf.data(exam(), submission(), %{show_correction: true})

      assert [%{"key" => "content", "doc" => doc}] = plain["sections"]
      assert inspect(doc) =~ "Meine Antwort"

      assert [%{"key" => "content", "doc" => doc}] = corrected["sections"]
      assert inspect(doc) =~ "Korrigiert"
    end

    test "has no sections when nothing is selected" do
      data = ExamSubmissionPdf.data(exam(), submission(), %{show_content: false})

      assert data["sections"] == []
    end
  end

  test "render/3 produces a PDF" do
    assert {:ok, "%PDF" <> _} =
             ExamSubmissionPdf.render(exam(), submission(), %{
               show_correction: true,
               show_sample_solution: true
             })
  end

  # Die Punktzahl am Feld ersetzt das „½" — sie muss den Typst-Pfad heil
  # durchlaufen, mit und ohne Musterlösung.
  test "render/3 draws the points of a judged field" do
    submission = %{submission() | block_verdicts: %{"a" => 1.5}}

    for sample? <- [true, false] do
      opts = %{show_correction: true, show_sample_solution: sample?}

      assert [%{"doc" => doc}] = ExamSubmissionPdf.data(exam(), submission, opts)["sections"]
      assert inspect(doc) =~ ~s("points" => "1.5")
      assert {:ok, "%PDF" <> _} = ExamSubmissionPdf.render(exam(), submission, opts)
    end
  end
end
