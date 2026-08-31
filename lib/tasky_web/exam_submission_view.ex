defmodule TaskyWeb.ExamSubmissionView do
  @moduledoc """
  Builds the sections of one exam submission for a read-only rendering — the
  PDF print view (`TaskyWeb.ExamLive.Print`) and the exam handed back to an
  assigned participant (`TaskyWeb.Student.ExamLive`).

  Both surfaces must show the same thing for the same options, which is the
  whole reason this lives in one place. The other reason is `normalize_options/1`:
  `Print` receives its options with **atom** keys (from `Tasky.Exams.PrintToken`),
  while the student view derives them from the exam's `return_show_*` boolean
  columns. Normalizing at the single entry point removes a class of bug that
  type-checks and renders an empty page.

  Die Musterlösung steht dabei am einzelnen Antwortfeld (siehe
  `Tasky.Exams.return_doc_for_learner/3`), genau wie in der Selbstkontrolle
  einer Lerneinheit. Als eigenes Dokument mit Überschrift erscheint sie nur
  noch, wenn der Inhalt gar nicht gezeigt wird — dann gibt es keine Felder, an
  die sie gehören könnte.

  Web layer rather than `lib/tasky`: no `Repo` involved, and the "Musterlösung"
  heading is UI copy.
  """

  alias Tasky.Exams
  alias Tasky.Exams.Exam
  alias Tasky.Exams.ExamSubmission

  @type section :: %{key: atom(), heading: String.t() | nil, doc_json: String.t()}

  @option_keys [
    :show_points_and_mark,
    :show_content,
    :show_correction,
    :show_sample_solution
  ]

  @defaults %{
    show_points_and_mark: true,
    show_content: true,
    show_correction: false,
    show_sample_solution: false
  }

  @doc """
  The TipTap docs to render, in order. Each section becomes its own viewer.
  """
  @spec sections(Exam.t(), ExamSubmission.t(), map()) :: [section()]
  def sections(%Exam{} = exam, %ExamSubmission{} = submission, opts) do
    opts = normalize_options(opts)

    []
    |> maybe_add_content_section(exam, submission, opts)
    |> maybe_add_sample_solution_section(exam, opts)
  end

  @doc """
  The options a returned exam was released with, as an atom-keyed map.
  """
  @spec options_from_exam(Exam.t()) :: map()
  def options_from_exam(%Exam{} = exam) do
    %{
      show_points_and_mark: exam.return_show_points_and_mark,
      show_content: exam.return_show_content,
      show_correction: exam.return_show_correction,
      show_sample_solution: exam.return_show_sample_solution
    }
  end

  @doc """
  Accepts atom- or string-keyed options and fills in the defaults. This is the
  single place either shape is tolerated.
  """
  @spec normalize_options(map() | keyword()) :: map()
  def normalize_options(opts) when is_list(opts), do: normalize_options(Map.new(opts))

  def normalize_options(opts) when is_map(opts) do
    Map.new(@option_keys, fn key ->
      value =
        case {Map.fetch(opts, key), Map.fetch(opts, Atom.to_string(key))} do
          {{:ok, value}, _} -> value
          {:error, {:ok, value}} -> value
          _ -> Map.fetch!(@defaults, key)
        end

      {key, !!value}
    end)
  end

  # The answers, optionally with the correction markers the teacher set and,
  # when the sample solution is released, the model answer under each field.
  defp maybe_add_content_section(sections, exam, submission, opts) do
    if opts.show_content do
      doc =
        if opts.show_correction do
          submission.corrected_content || submission.content
        else
          submission.content
        end

      doc =
        if opts.show_sample_solution,
          do: with_sample_solution(exam, submission, doc, opts),
          else: doc

      sections ++ [build_section(:content, nil, doc_nodes(doc))]
    else
      sections
    end
  end

  # Die Musterlösung steht am Antwortfeld statt in einem zweiten Dokument. Das
  # Verdikt kommt nur mit, wenn auch die Korrektur freigegeben ist — es *ist*
  # die Korrektur, und `show_correction` entscheidet über sie.
  defp with_sample_solution(exam, submission, doc, opts) do
    verdicts = if opts.show_correction, do: Exams.learner_verdicts(exam, submission), else: %{}

    Exams.return_doc_for_learner(exam, doc, verdicts)
  end

  # Nur noch als Rückfall: ohne angezeigten Inhalt gibt es kein Antwortdokument,
  # an das sich die Musterlösung hängen liesse.
  defp maybe_add_sample_solution_section(sections, exam, opts) do
    if opts.show_sample_solution and not opts.show_content do
      sections ++
        [
          build_section(
            :sample,
            "Musterlösung",
            doc_nodes(Exams.sample_solution_doc_for_learner(exam))
          )
        ]
    else
      sections
    end
  end

  defp build_section(key, heading, nodes) do
    doc = %{"type" => "doc", "content" => nodes}
    %{key: key, heading: heading, doc_json: Jason.encode!(doc)}
  end

  defp doc_nodes(doc) when is_map(doc), do: Map.get(doc, "content", [])
  defp doc_nodes(_), do: []
end
