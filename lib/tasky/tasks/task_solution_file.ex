defmodule Tasky.Tasks.TaskSolutionFile do
  @moduledoc """
  Eine Musterlösungs-Datei einer Lerneinheit — etwa das korrekt formatierte
  Word-Dokument zu einer Formatierungsaufgabe.

  Aufbau wie `Tasky.Tasks.TaskAttachment`, aber mit einem anderen Tor: Anhänge
  liegen öffentlich unter `/uploads/...`, Lösungsdateien werden nur an
  Lernende ausgeliefert, für die `Tasky.Tasks.solution_visible?/2` wahr ist.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "task_solution_files" do
    field :stored_filename, :string
    field :original_name, :string
    field :content_type, :string
    field :size, :integer
    field :position, :integer, default: 0

    belongs_to :task, Tasky.Tasks.Task

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(file, attrs) do
    file
    |> cast(attrs, [:stored_filename, :original_name, :content_type, :size, :position])
    |> validate_required([:stored_filename, :original_name, :content_type, :size])
    |> validate_length(:original_name, max: 255)
    |> unique_constraint(:stored_filename)
  end
end
