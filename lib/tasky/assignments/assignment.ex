defmodule Tasky.Assignments.Assignment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "assignments" do
    field :name, :string
    field :link, :string
    field :status, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, [:name, :link, :status])
    |> validate_required([:name, :link, :status])
  end
end
