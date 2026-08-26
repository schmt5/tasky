defmodule Tasky.Classes.Class do
  @moduledoc """
  A class belongs to one organization; the teachers of that organization all see
  it and every student in it. A student's organization *is* this class's
  organization — see `Tasky.Organizations`.

  `organization_id` is never cast by `changeset/2`: for a teacher it is taken
  from their own organization, and only an admin may name one explicitly through
  `admin_changeset/2`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "classes" do
    field :name, :string
    field :slug, :string

    belongs_to :organization, Tasky.Organizations.Organization
    has_many :students, Tasky.Accounts.User, foreign_key: :class_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(class, attrs) do
    class
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> generate_slug()
    |> validate_required([:slug])
    |> unique_constraint(:slug)
  end

  @doc """
  Like `changeset/2` but lets an admin move the class between organizations.

  Only reachable from the admin path in `Tasky.Classes` — a teacher must never
  be able to reassign a class.
  """
  def admin_changeset(class, attrs) do
    class
    |> changeset(attrs)
    |> cast(attrs, [:organization_id])
    |> foreign_key_constraint(:organization_id)
  end

  defp generate_slug(changeset) do
    case get_change(changeset, :name) do
      nil ->
        changeset

      name ->
        slug = slugify(name)
        put_change(changeset, :slug, slug)
    end
  end

  @doc """
  Converts a string into a URL-friendly slug.

  ## Examples

      iex> Tasky.Classes.Class.slugify("Klasse 5a")
      "klasse-5a"

      iex> Tasky.Classes.Class.slugify("Mathematik 2023/24")
      "mathematik-2023-24"

      iex> Tasky.Classes.Class.slugify("Deutsch & Englisch")
      "deutsch-englisch"
  """
  def slugify(string) do
    string
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[^a-z0-9\s-]/u, "")
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end
end
