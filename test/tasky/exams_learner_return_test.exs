defmodule Tasky.ExamsLearnerReturnTest do
  @moduledoc """
  Was die/der Lernende von einer zurückgegebenen Prüfung sieht: die Verdikte am
  Antwortfeld und die Musterlösung direkt darunter.

  Reine Struct-Arithmetik — beide Funktionen fassen kein Repo an.
  """
  use ExUnit.Case, async: true

  alias Tasky.Exams
  alias Tasky.Exams.Exam
  alias Tasky.Exams.ExamSubmission

  defp exam(attrs \\ %{}) do
    struct(
      %Exam{
        answer_mode: "answer_fields",
        content: doc([heading(), answer_block("a", "")]),
        sample_solution: %{"a" => [paragraph("pdf;.pdf")]}
      },
      attrs
    )
  end

  defp submission(attrs) do
    struct(%ExamSubmission{content: %{}, corrected_content: %{}, block_verdicts: %{}}, attrs)
  end

  defp doc(nodes), do: %{"type" => "doc", "content" => nodes}

  defp heading do
    %{
      "type" => "heading",
      "attrs" => %{"level" => 3, "partId" => "q-1"},
      "content" => [%{"type" => "text", "text" => "Frage 1"}]
    }
  end

  defp answer_block(id, text) do
    %{
      "type" => "answerBlock",
      "attrs" => %{"answerId" => id},
      "content" => [paragraph(text)]
    }
  end

  defp paragraph(text),
    do: %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}

  describe "learner_verdicts/2" do
    test "reads the teacher's explicit verdict" do
      submission =
        submission(%{
          corrected_content: doc([heading(), answer_block("a", "pdf")]),
          block_verdicts: %{"a" => "correct"}
        })

      assert Exams.learner_verdicts(exam(), submission) == %{"a" => "correct"}
    end

    # `block_verdicts` ist die verbindliche Quelle — der Marker im Text ist nur
    # ihr Abbild und darf sie nicht überstimmen.
    test "block_verdicts beats a contradicting text marker" do
      submission =
        submission(%{
          corrected_content: doc([heading(), answer_block("a", "pdf ❌")]),
          block_verdicts: %{"a" => "correct"}
        })

      assert Exams.learner_verdicts(exam(), submission) == %{"a" => "correct"}
    end

    test "falls back to the text marker when no verdict was stored" do
      submission = submission(%{corrected_content: doc([heading(), answer_block("a", "pdf ✅")])})

      assert Exams.learner_verdicts(exam(), submission) == %{"a" => "correct"}
    end

    test "an unmarked, unjudged block gets no verdict at all" do
      submission = submission(%{corrected_content: doc([heading(), answer_block("a", "pdf")])})

      assert Exams.learner_verdicts(exam(), submission) == %{}
    end

    # Teilpunkte gibt es nur in Prüfungen. Aufgelöst werden sie über dasselbe
    # Blockmaximum, mit dem die Lehrperson sie vergeben hat.
    test "manual points resolve against the block maximum" do
      exam = exam(%{sample_solution_points: %{"q-1" => 4}})

      for {points, expected} <- [{0, "wrong"}, {2, "half"}, {4, "correct"}] do
        submission =
          submission(%{
            corrected_content: doc([heading(), answer_block("a", "pdf")]),
            block_verdicts: %{"a" => points}
          })

        assert Exams.learner_verdicts(exam, submission) == %{"a" => expected}
      end
    end

    test "without configured points, partial points stay 'half'" do
      submission =
        submission(%{
          corrected_content: doc([heading(), answer_block("a", "pdf")]),
          block_verdicts: %{"a" => 2}
        })

      assert Exams.learner_verdicts(exam(), submission) == %{"a" => "half"}
    end

    test "falls back to the raw content when nothing was corrected" do
      submission =
        submission(%{
          content: doc([heading(), answer_block("a", "pdf")]),
          corrected_content: %{},
          block_verdicts: %{"a" => "wrong"}
        })

      assert Exams.learner_verdicts(exam(), submission) == %{"a" => "wrong"}
    end
  end

  describe "return_doc_for_learner/3" do
    test "hangs the sample solution under the answer field" do
      base = doc([heading(), answer_block("a", "pdf")])

      assert %{"content" => [_heading, answer, hint]} =
               Exams.return_doc_for_learner(exam(), base, %{})

      assert answer["type"] == "answerBlock"
      assert %{"type" => "solutionHint", "content" => [twin]} = hint
      assert twin["content"] == [paragraph("pdf, .pdf")]
    end

    # Der Zwilling darf die id nicht mitschleppen: sie stünde sonst zweimal im
    # Dokument, und bewertet wird nur das echte Feld.
    test "the twin carries neither answerId nor verdict" do
      base = doc([heading(), answer_block("a", "pdf")])

      %{"content" => [_heading, _answer, %{"content" => [twin]}]} =
        Exams.return_doc_for_learner(exam(), base, %{"a" => "wrong"})

      assert twin["attrs"] == %{}
    end

    test "the verdict lands as an attribute on the answer node" do
      base = doc([heading(), answer_block("a", "pdf")])

      %{"content" => [_heading, answer, _hint]} =
        Exams.return_doc_for_learner(exam(), base, %{"a" => "half"})

      assert answer["attrs"]["verdict"] == "half"
    end

    # Sonst trägt jedes korrigierte Feld zwei Marker: den Text aus der Korrektur
    # und das Zeichen, das das Stylesheet aus `data-verdict` setzt.
    test "the ✅/🟡/❌ text markers of the correction are stripped" do
      base = doc([heading(), answer_block("a", "pdf ✅")])

      %{"content" => [_heading, answer, _hint]} =
        Exams.return_doc_for_learner(exam(), base, %{"a" => "correct"})

      assert answer["content"] == [paragraph("pdf")]
    end

    # Ohne Verdikte gibt es keine Korrektur, die den Text ersetzen würde — was
    # die/der Lernende geschrieben hat, bleibt unangetastet.
    test "without verdicts the answer text is left alone" do
      base = doc([heading(), answer_block("a", "pdf ✅")])

      %{"content" => [_heading, answer, _hint]} =
        Exams.return_doc_for_learner(exam(), base, %{})

      assert answer["content"] == [paragraph("pdf ✅")]
    end

    test "an empty sample solution produces no hint" do
      exam = exam(%{sample_solution: %{}})
      base = doc([heading(), answer_block("a", "pdf")])

      assert %{"content" => [_heading, answer]} = Exams.return_doc_for_learner(exam, base, %{})
      assert answer["type"] == "answerBlock"
    end
  end
end
