defmodule Tasky.Exams.Progress do
  @moduledoc """
  Der Zwischenstand einer Prüfung: pro Teil und Abgabe, ob schon etwas
  geantwortet wurde und — bei automatisch korrigierten Teilen — ob es stimmt.

  Rein funktional und bewusst getrennt vom Speicherpfad der Lernenden
  (`Exams.update_exam_submission_content/2`): gerechnet wird im Prozess der
  Lehrperson, die das Raster offen hat, nie im Autosave-Request.

  Die Farben sind eine Momentaufnahme, keine Bewertung. Ein leeres Feld zählt
  als falsch, eine halb ausgefüllte Ankreuzaufgabe ist darum `:partial`; und
  ein nicht angekreuztes Kästchen sieht aus wie „nicht beantwortet“.
  """

  alias Tasky.AI.NodePatcher
  alias Tasky.Correction.Choice
  alias Tasky.Correction.StringComparator
  alias Tasky.Exams
  alias Tasky.Exams.Exam

  @type status :: :not_started | :answered | :correct | :partial | :wrong

  @doc """
  Alles, was pro Prüfung nur einmal gerechnet werden muss: die Teile (`id`,
  `label`), die Musterlösung pro Teil und die Vergleichsoptionen der
  automatisch korrigierten Teile.

  Wie in `Exams.list_bulk_correction_jobs/2` wird ein `free_document` nie
  automatisch korrigiert.
  """
  def prepare(%Exam{} = exam) do
    parts =
      (exam.content || %{})
      |> Exams.split_content_into_parts(exam.answer_mode)
      |> Enum.map(&Map.take(&1, [:id, :label]))

    auto =
      if Exams.free_document?(exam) do
        %{}
      else
        sample_parts =
          exam
          |> Exams.sample_solution_doc()
          |> Exams.split_content_into_parts(exam.answer_mode)
          |> Map.new(&{&1.id, &1.nodes})

        config = exam.ai_correction_config || %{}

        for part_id <- Exams.auto_correct_part_ids(exam), into: %{} do
          {part_id,
           %{
             sample_nodes: Map.get(sample_parts, part_id, []),
             match_opts: StringComparator.match_opts(Map.get(config, part_id))
           }}
        end
      end

    %{parts: parts, auto: auto, answer_mode: exam.answer_mode}
  end

  @doc """
  `%{part_id => status}` für den Inhalt einer Abgabe. Jeder Teil aus
  `prepare/1` bekommt einen Eintrag; fehlt er in der Abgabe, ist er
  `:not_started`.
  """
  @spec statuses(map(), map() | nil) :: %{String.t() => status()}
  def statuses(%{parts: parts} = prepared, content) do
    submission_parts =
      if is_map(content) and map_size(content) > 0 do
        content
        |> Exams.split_content_into_parts(prepared.answer_mode)
        |> Map.new(&{&1.id, &1.nodes})
      else
        %{}
      end

    Map.new(parts, fn part ->
      nodes = Map.get(submission_parts, part.id, [])
      {part.id, part_status(nodes, Map.get(prepared.auto, part.id))}
    end)
  end

  defp part_status(nodes, auto) do
    choices = Choice.groups(nodes)

    cond do
      not Enum.any?(NodePatcher.list_answer_blocks(nodes), &started?(&1, choices)) -> :not_started
      is_nil(auto) -> :answered
      true -> verdict_status(nodes, auto)
    end
  end

  # A radio's `text` is the chosen option's label, which may well be empty (a
  # radio in a table cell): whether one is chosen is asked of the group.
  defp started?(%{type: "choice", answer_id: gid}, choices),
    do: choices |> Map.get(gid) |> Choice.checked_options() != []

  defp started?(%{type: "taskItem", checked: checked}, _choices), do: checked == true
  defp started?(%{text: text}, _choices) when is_binary(text), do: String.trim(text) != ""
  defp started?(_block, _choices), do: false

  defp verdict_status(nodes, %{sample_nodes: sample_nodes, match_opts: match_opts}) do
    {annotated, _count} = NodePatcher.annotate(nodes)

    {:ok, %{verdicts: verdicts}} =
      StringComparator.correct_part(annotated, sample_nodes, nil, match_opts)

    case verdicts |> Map.values() |> Enum.frequencies() do
      %{"correct" => _} = counts when map_size(counts) == 1 -> :correct
      %{"correct" => _} -> :partial
      # Nothing to compare against (e.g. a radio group without a sample choice).
      counts when map_size(counts) == 0 -> :answered
      _ -> :wrong
    end
  end
end
