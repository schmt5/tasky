defmodule Tasky.TaskPdf do
  @moduledoc """
  A learning unit as a PDF (`priv/typst/task.typ`), in one of two variants:

    * `:worksheet` — the blank sheet to fill in by hand, sized like the paper
      version of an exam (`Tasky.ExamPaper.worksheet_doc/1`).
    * `:solution` — the same content with the sample solution filled in
      (`Tasky.Tasks.sample_solution_doc/1`, what the solution editor loads).

  Only the content is printed — no head, no name fields.
  """

  alias Tasky.ExamPaper
  alias Tasky.Tasks
  alias Tasky.Tasks.Task

  @type variant :: :worksheet | :solution

  @doc "Renders `task` as `variant`: `{:ok, pdf}` or `{:error, message}`."
  @spec render(Task.t(), variant()) :: {:ok, binary()} | {:error, String.t()}
  def render(%Task{} = task, variant) do
    Tasky.PDF.render("task", data(task, variant))
  end

  @doc "The template data for `render/2`, exposed for tests."
  @spec data(Task.t(), variant()) :: map()
  def data(%Task{} = task, :worksheet) do
    %{
      "title" => "#{task.name} – Arbeitsblatt",
      "mode" => "paper",
      "doc" => ExamPaper.worksheet_doc(task.content)
    }
  end

  def data(%Task{} = task, :solution) do
    %{
      "title" => "#{task.name} – Musterlösung",
      "mode" => "review",
      "doc" => Tasks.sample_solution_doc(task)
    }
  end
end
