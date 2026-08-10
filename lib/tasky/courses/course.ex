defmodule Tasky.Courses.Course do
  use Ecto.Schema
  import Ecto.Changeset

  schema "courses" do
    field :name, :string
    field :description, :string

    # Unguessable slug for the public Markdown export. Never cast from user
    # input — only `Tasky.Courses.ensure_share_slug/2` sets it.
    field :share_slug, :string

    # Anonymer Feedback-Briefkasten (`Tasky.Feedback`). Startet geschlossen; die
    # Lehrperson öffnet ihn bewusst im Kursformular.
    field :feedback_box_enabled, :boolean, default: false

    # Kurs-Katalog: `nil` = nicht im Katalog. Bewusst NICHT in `changeset/2`
    # gecastet — wie `share_slug`: nur `Tasky.Courses.publish_to_catalog/2` und
    # `unpublish_from_catalog/2` setzen das Feld. So kann eine Kopie die
    # Veröffentlichung auch dann nicht erben, wenn irgendwann jemand die
    # `attrs`-Map in `Tasky.Courses.duplicate_course_records/3` erweitert.
    field :catalog_published_at, :utc_datetime

    # Nur von `Tasky.Courses.list_catalog_courses/1` gefüllt (COUNT über die
    # Lerneinheiten): die Katalogliste braucht die Anzahl, nicht die Inhalte.
    field :unit_count, :integer, virtual: true

    belongs_to :teacher, Tasky.Accounts.User, foreign_key: :teacher_id
    has_many :tasks, Tasky.Tasks.Task

    many_to_many :students, Tasky.Accounts.User,
      join_through: "course_enrollments",
      join_keys: [course_id: :id, student_id: :id]

    timestamps(type: :utc_datetime)
  end

  @doc "True, wenn der Kurs im Kurs-Katalog sichtbar ist."
  def catalog_published?(%__MODULE__{catalog_published_at: nil}), do: false
  def catalog_published?(%__MODULE__{}), do: true

  @doc false
  def changeset(course, attrs) do
    course
    |> cast(attrs, [:name, :description, :feedback_box_enabled])
    |> validate_required([:name])
    |> validate_length(:name, min: 3, max: 255)
    |> validate_length(:description, max: 1000)
  end

  @doc false
  def create_changeset(course, attrs, scope) do
    course
    |> changeset(attrs)
    |> put_change(:teacher_id, scope.user.id)
  end
end
