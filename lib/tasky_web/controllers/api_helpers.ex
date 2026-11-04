defmodule TaskyWeb.ApiHelpers do
  @moduledoc """
  Shared plumbing for the JSON content/image API controllers: uniform error
  responses and rendering of context save results. New endpoints use these
  helpers so none can forget the authorize/translate steps.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @doc "Uniform JSON error response."
  def json_error(conn, status, message) do
    conn |> put_status(status) |> json(%{error: message})
  end

  @doc """
  Renders a context save result: `{:ok, struct}` becomes
  `%{ok: true, updated_at: ...}`; `{:error, :unauthorized}` a 403; a changeset
  a 422 with translated details.
  """
  def render_save_result(conn, result) do
    case result do
      {:ok, updated} ->
        json(conn, %{ok: true, updated_at: updated.updated_at})

      {:error, :unauthorized} ->
        json_error(conn, :forbidden, "Keine Berechtigung.")

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Ungültiger Inhalt.", details: translate_errors(changeset)})

      {:error, _other} ->
        json_error(conn, :unprocessable_entity, "Speichern fehlgeschlagen.")
    end
  end

  @audio_play_errors %{
    exhausted: {:conflict, "Alle Durchgänge sind gebraucht."},
    already_submitted: {:conflict, "Die Abgabe ist bereits eingereicht."},
    exam_not_running: {:conflict, "Die Prüfung läuft nicht."},
    not_editable: {:conflict, "Die Aufgabe ist bereits als erledigt markiert."},
    not_found: {:not_found, "Audio nicht gefunden."},
    file_missing: {:not_found, "Die Audiodatei fehlt. Bitte melde dich bei deiner Lehrperson."},
    unauthorized: {:forbidden, "Keine Berechtigung."}
  }

  @doc """
  Renders the result of an audio play call (`start`/`progress`/`finish` in
  `Tasky.Exams` and `Tasky.Tasks`): the player's view, or why not.
  """
  def render_audio_play(conn, {:ok, view}), do: json(conn, view)

  def render_audio_play(conn, {:error, reason}) do
    {status, message} =
      Map.get(@audio_play_errors, reason, {:unprocessable_entity, "Speichern fehlgeschlagen."})

    json_error(conn, status, message)
  end

  @doc "Flattens changeset errors into a `%{field => [message]}` map."
  def translate_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, &TaskyWeb.CoreComponents.translate_error/1)
  end
end
