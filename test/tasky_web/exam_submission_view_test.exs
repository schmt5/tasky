defmodule TaskyWeb.ExamSubmissionViewTest do
  use Tasky.DataCase, async: true

  import Tasky.ExamsFixtures

  alias TaskyWeb.ExamSubmissionView

  defp doc(text) do
    %{
      "type" => "doc",
      "content" => [
        %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}
      ]
    }
  end

  defp submission_with(fields) do
    struct(Tasky.Exams.ExamSubmission, Map.merge(%{content: %{}, corrected_content: %{}}, fields))
  end

  defp exam, do: exam_fixture()

  # Ein Antwortfeld braucht eine Frage-Überschrift über sich: erst die macht es
  # zum Teil eines Parts (siehe `Tasky.ExamDoc.split_content_into_parts/2`).
  defp question_doc(answer \\ "") do
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

  defp sample,
    do: %{
      "a" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "pdf;.pdf"}]}]
    }

  describe "normalize_options/1" do
    test "atom and string keys produce the same result" do
      atoms = %{show_content: true, show_correction: true, show_sample_solution: false}

      strings = %{
        "show_content" => true,
        "show_correction" => true,
        "show_sample_solution" => false
      }

      assert ExamSubmissionView.normalize_options(atoms) ==
               ExamSubmissionView.normalize_options(strings)
    end

    test "fills in the defaults for missing keys" do
      assert ExamSubmissionView.normalize_options(%{}) == %{
               show_points_and_mark: true,
               show_content: true,
               show_correction: false,
               show_sample_solution: false
             }
    end

    test "coerces to booleans" do
      assert ExamSubmissionView.normalize_options(%{show_content: nil}).show_content == false
      assert ExamSubmissionView.normalize_options(%{show_content: "yes"}).show_content == true
    end

    test "accepts a keyword list" do
      assert ExamSubmissionView.normalize_options(show_content: false).show_content == false
    end
  end

  describe "options_from_exam/1" do
    test "reads the stored return flags" do
      exam = %Tasky.Exams.Exam{
        return_show_points_and_mark: false,
        return_show_content: true,
        return_show_correction: true,
        return_show_sample_solution: false
      }

      assert ExamSubmissionView.options_from_exam(exam) == %{
               show_points_and_mark: false,
               show_content: true,
               show_correction: true,
               show_sample_solution: false
             }
    end

    # The round trip that a :map column would have broken.
    test "round-trips through normalize_options/1" do
      exam = %Tasky.Exams.Exam{
        return_show_points_and_mark: true,
        return_show_content: true,
        return_show_correction: true,
        return_show_sample_solution: true
      }

      opts = ExamSubmissionView.options_from_exam(exam)
      assert ExamSubmissionView.normalize_options(opts) == opts
    end
  end

  describe "sections/3" do
    test "content only" do
      submission = submission_with(%{content: doc("Meine Antwort")})

      assert [%{key: :content, heading: nil, doc_json: json}] =
               ExamSubmissionView.sections(exam(), submission, %{show_content: true})

      assert json =~ "Meine Antwort"
    end

    test "show_correction renders the corrected content" do
      submission =
        submission_with(%{content: doc("Rohantwort"), corrected_content: doc("Korrigiert")})

      [%{doc_json: json}] =
        ExamSubmissionView.sections(exam(), submission, %{
          show_content: true,
          show_correction: true
        })

      assert json =~ "Korrigiert"
      refute json =~ "Rohantwort"
    end

    test "show_correction falls back to the raw content when nothing was corrected" do
      submission = submission_with(%{content: doc("Rohantwort"), corrected_content: nil})

      [%{doc_json: json}] =
        ExamSubmissionView.sections(exam(), submission, %{
          show_content: true,
          show_correction: true
        })

      assert json =~ "Rohantwort"
    end

    test "show_correction without show_content yields no content section" do
      submission = submission_with(%{content: doc("Meine Antwort")})

      assert ExamSubmissionView.sections(exam(), submission, %{
               show_content: false,
               show_correction: true
             }) == []
    end

    # Die Musterlösung gehört ans Antwortfeld, nicht in ein zweites Dokument:
    # sonst muss zum Vergleichen gescrollt und zugeordnet werden.
    test "the sample solution sits inside the content section, not next to it" do
      exam = exam_fixture(attrs: %{content: question_doc(), sample_solution: sample()})
      submission = submission_with(%{content: question_doc("pdf")})

      assert [%{key: :content, heading: nil, doc_json: json}] =
               ExamSubmissionView.sections(exam, submission, %{
                 show_content: true,
                 show_sample_solution: true
               })

      assert json =~ "solutionHint"
      assert json =~ "pdf, .pdf"
    end

    test "the standalone section is what remains when the content is hidden" do
      exam = exam_fixture(attrs: %{content: question_doc(), sample_solution: sample()})
      submission = submission_with(%{content: question_doc("pdf")})

      assert [%{key: :sample, heading: "Musterlösung", doc_json: json}] =
               ExamSubmissionView.sections(exam, submission, %{
                 show_content: false,
                 show_sample_solution: true
               })

      refute json =~ "solutionHint"
    end

    # Das Verdikt *ist* die Korrektur — es grün/rot zu zeigen, während die
    # Korrektur ausgeblendet ist, würde `show_correction` aushebeln.
    test "the verdict rides along only when the correction is released" do
      exam = exam_fixture(attrs: %{content: question_doc(), sample_solution: sample()})

      submission =
        submission_with(%{
          content: question_doc("pdf"),
          corrected_content: question_doc("pdf ✅"),
          block_verdicts: %{"a" => "correct"}
        })

      opts = %{show_content: true, show_sample_solution: true}

      [%{doc_json: without}] = ExamSubmissionView.sections(exam, submission, opts)
      refute without =~ "verdict"

      [%{doc_json: with_correction}] =
        ExamSubmissionView.sections(exam, submission, Map.put(opts, :show_correction, true))

      assert with_correction =~ ~s("verdict":"correct")
      # Der Marker kommt aus dem Stylesheet; als Text stünde er doppelt da.
      refute with_correction =~ "✅"
    end

    test "no options means no sections" do
      submission = submission_with(%{content: doc("Meine Antwort")})

      assert ExamSubmissionView.sections(exam(), submission, %{
               show_content: false,
               show_sample_solution: false
             }) == []
    end

    # Das `;` trennt mehrere gültige Antworten und ist ein reines Autorenformat.
    # Wer die zurückgegebene Prüfung liest, kann damit nichts anfangen.
    test "the sample solution spells out alternative answers instead of showing the `;`" do
      content = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "answerBlock",
            "attrs" => %{"answerId" => "a"},
            "content" => [%{"type" => "paragraph"}]
          }
        ]
      }

      sample = %{
        "a" => [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "pdf;.pdf"}]}
        ]
      }

      exam = exam_fixture(attrs: %{content: content, sample_solution: sample})
      submission = submission_with(%{content: doc("Meine Antwort")})

      assert [%{key: :sample, doc_json: json}] =
               ExamSubmissionView.sections(exam, submission, %{
                 show_content: false,
                 show_sample_solution: true
               })

      assert json =~ "pdf, .pdf"
      refute json =~ ";"
    end
  end
end
