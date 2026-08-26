defmodule Tasky.Organizations.Organization do
  @moduledoc """
  An organization groups teachers, classes and — through those classes — the
  students. It is the tenant boundary for everything class- and student-shaped;
  courses, learning units and exams stay owner-scoped (see `Tasky.Policy`).

  `invite_token` is the credential that turns a visitor into a **teacher** of
  this organization, with full sight of its classes and students. That makes it
  the most valuable credential in the app — hence a random token rather than the
  guessable `slug`, and hence `rotate_invite_token/2`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Tasky.Classes.Class

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :invite_token, :string

    has_many :users, Tasky.Accounts.User
    has_many :classes, Class

    timestamps(type: :utc_datetime)
  end

  @doc """
  Casts the name only. `slug` is derived from it and `invite_token` is set
  programmatically by `Tasky.Organizations.create_organization/2`.
  """
  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name])
    |> validate_required([:name], message: "darf nicht leer sein")
    |> validate_length(:name,
      min: 1,
      max: 100,
      message: "muss zwischen 1 und 100 Zeichen lang sein"
    )
    |> generate_slug()
    |> validate_required([:slug])
    |> unique_constraint(:slug)
  end

  defp generate_slug(changeset) do
    case get_change(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :slug, Class.slugify(name))
    end
  end
end
