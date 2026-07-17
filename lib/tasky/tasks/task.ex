defmodule Tasky.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tasks" do
    field :name, :string
    field :position, :integer
    field :status, :string
    field :locked, :boolean, default: false
    field :content, :map
    field :user_id, :id

    belongs_to :course, Tasky.Courses.Course
    has_many :submissions, Tasky.Tasks.TaskSubmission
    has_many :attachments, Tasky.Tasks.TaskAttachment
    has_many :upload_fields, Tasky.Tasks.TaskUploadField

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(task, attrs, user_scope) do
    task
    |> cast(attrs, [:name, :position, :status, :course_id, :locked])
    |> validate_required([:name, :position, :status])
    |> put_change(:user_id, user_scope.user.id)
  end

  @doc """
  Changeset for saving the learning unit's Tiptap content doc.
  """
  def content_changeset(task, content) when is_map(content) do
    change(task, content: content)
  end
end
