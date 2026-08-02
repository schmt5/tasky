defmodule Tasky.Courses.CourseExport do
  @moduledoc """
  Assembles a whole course into one Markdown document — the body served at
  `/share/course/:share_slug` for AI tools to read ("lies dir diesen Kurs
  durch und erstelle Prüfungsaufgaben").

  Pure: a course struct and its learning units in, a string out. The units
  must come from `Tasky.Tasks.list_tasks_for_export/1`, which orders them by
  position and preloads attachments and upload fields.

  Every unit is exported, including drafts, archived and locked ones — an
  annotated line says which is which, and the reader decides what to weigh.
  """

  alias Tasky.Courses.Course
  alias Tasky.TiptapMarkdown

  @doc """
  Renders the course as Markdown. `opts` are passed through to
  `Tasky.TiptapMarkdown.to_markdown/2` (notably `:base_url`).
  """
  def to_markdown(%Course{} = course, tasks, opts \\ []) when is_list(tasks) do
    [header(course, tasks) | Enum.map(Enum.with_index(tasks, 1), &unit(&1, opts))]
    |> Enum.join("\n\n---\n\n")
    |> Kernel.<>("\n")
  end

  defp header(course, tasks) do
    [
      "# " <> to_string(course.name),
      description(course),
      summary(tasks),
      legend(tasks)
    ]
    |> compact_join()
  end

  defp description(%Course{description: description})
       when is_binary(description) and description != "" do
    String.trim(description)
  end

  defp description(_course), do: nil

  defp summary([]), do: "_Dieser Kurs enthält noch keine Lerneinheiten._"

  defp summary(tasks) do
    "_Automatisch erzeugter Export von #{length(tasks)} #{unit_word(tasks)} dieses Kurses._"
  end

  defp unit_word([_single]), do: "Lerneinheit"
  defp unit_word(_tasks), do: "Lerneinheiten"

  # Only explain the markers that actually occur, so short courses stay clean.
  defp legend([]), do: nil

  defp legend(_tasks) do
    "_Legende: `[____]` steht für eine Lücke, die Lernende ausfüllen; " <>
      "`_[Antwortfeld]_` für ein freies Antwortfeld; `- [ ]` für eine Checkbox._"
  end

  defp unit({task, index}, opts) do
    [
      "## #{index}. #{task.name}",
      status_line(task),
      content(task, opts),
      attachments(task),
      upload_fields(task)
    ]
    |> compact_join()
  end

  defp status_line(task) do
    markers =
      [
        status_marker(task.status),
        task.extended && "Erweiterte (freiwillige) Lerneinheit",
        task.locked && "Für Lernende noch nicht freigeschaltet"
      ]
      |> Enum.filter(&is_binary/1)

    case markers do
      [] -> nil
      markers -> "_" <> Enum.join(markers, " · ") <> "_"
    end
  end

  defp status_marker("draft"), do: "Entwurf"
  defp status_marker("archived"), do: "Archiviert"
  defp status_marker(_status), do: nil

  defp content(task, opts) do
    case TiptapMarkdown.to_markdown(task.content, opts) do
      "" -> "_Diese Lerneinheit enthält noch keinen Inhalt._"
      markdown -> markdown
    end
  end

  defp attachments(%{attachments: [_ | _] = attachments}) do
    "**Anhänge:** " <> Enum.map_join(attachments, ", ", & &1.original_name)
  end

  defp attachments(_task), do: nil

  defp upload_fields(%{upload_fields: [_ | _] = fields}) do
    "**Von Lernenden abzugebende Dateien:** " <> Enum.map_join(fields, ", ", &upload_field/1)
  end

  defp upload_fields(_task), do: nil

  defp upload_field(field) do
    label = field.label
    if field.required, do: label <> " (Pflicht)", else: label
  end

  defp compact_join(parts) do
    parts
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join("\n\n")
  end
end
