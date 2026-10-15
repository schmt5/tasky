defmodule Tasky.ExamPaperPdf do
  @moduledoc """
  The paper version of an exam as a PDF (`priv/typst/paper.typ`).

  The document is the same one the paper view in the browser shows —
  `Tasky.ExamPaper.paper_doc/2` with the teacher's box sizes — so the PDF and
  the browser-print fallback (`TaskyWeb.ExamLive.Paper`) print the same exam.
  """

  alias Tasky.ExamPaper
  alias Tasky.Exams
  alias Tasky.Exams.Exam
  alias Tasky.Grading

  @doc "Renders the paper version of `exam`: `{:ok, pdf}` or `{:error, message}`."
  @spec render(Exam.t()) :: {:ok, binary()} | {:error, String.t()}
  def render(%Exam{} = exam) do
    Tasky.PDF.render("paper", data(exam))
  end

  @doc "The template data for `render/1`, exposed for tests."
  @spec data(Exam.t()) :: map()
  def data(%Exam{} = exam) do
    free_document = Exams.free_document?(exam)

    %{
      "exam_name" => exam.name,
      "max_points" =>
        case Exams.grading_max_points(exam) do
          nil -> nil
          max_points -> Grading.format_points(max_points)
        end,
      "doc" =>
        ExamPaper.paper_doc(exam.content,
          layout: exam.paper_layout,
          sample_solution_points: exam.sample_solution_points,
          sample_solution_block_points: exam.sample_solution_block_points,
          answer_mode: exam.answer_mode
        ),
      "free_document" => free_document,
      "lined_pages" => if(free_document, do: ExamPaper.lined_page_count(), else: 0),
      "rules_per_page" => ExamPaper.rules_per_page()
    }
  end
end
