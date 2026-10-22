defmodule TaskyWeb.ExamSubmissionPdf do
  @moduledoc """
  One graded submission as a PDF (`priv/typst/submission.typ`) — a file per
  student in the grading export (`Tasky.Exams.ExportRunner`).

  The sections come from `TaskyWeb.ExamSubmissionView`, the same module the
  returned exam in the student view uses, so both show the same thing for the
  same options. Points, max points and the mark all come out of
  `Tasky.Exams.grading_result/2`, so the PDF cannot print a different mark
  than the grading table shows.
  """

  alias Tasky.Exams
  alias Tasky.Exams.Exam
  alias Tasky.Exams.ExamSubmission
  alias Tasky.Grading
  alias TaskyWeb.ExamSubmissionView

  @doc """
  Renders `submission` with the export options (`show_points_and_mark`,
  `show_content`, `show_correction`, `show_sample_solution`).
  """
  @spec render(Exam.t(), ExamSubmission.t(), map()) :: {:ok, binary()} | {:error, String.t()}
  def render(%Exam{} = exam, %ExamSubmission{} = submission, opts) do
    Tasky.PDF.render("submission", data(exam, submission, opts))
  end

  @doc "The template data for `render/3`, exposed for tests."
  @spec data(Exam.t(), ExamSubmission.t(), map()) :: map()
  def data(%Exam{} = exam, %ExamSubmission{} = submission, opts) do
    opts = ExamSubmissionView.normalize_options(opts)

    %{
      points: points,
      total_points: total_points,
      points_for_six: points_for_six,
      effective_mark: mark
    } =
      Exams.grading_result(exam, submission)

    %{
      "exam_name" => exam.name,
      "student_name" => String.trim("#{submission.firstname} #{submission.lastname}"),
      "show_points_and_mark" => opts.show_points_and_mark,
      "points" => Grading.format_points(points),
      "max_points" => total_points && Grading.format_points(total_points),
      "six_hint" => Grading.six_hint(total_points, points_for_six),
      "mark" => Grading.format_mark(mark),
      "sections" =>
        exam
        |> ExamSubmissionView.sections(submission, opts)
        |> Enum.map(fn section ->
          %{
            "key" => Atom.to_string(section.key),
            "heading" => section.heading,
            "doc" => section.doc
          }
        end)
    }
  end
end
