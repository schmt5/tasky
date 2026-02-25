defmodule Tasky.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true
    field :role, :string, default: "student"

    has_many :task_submissions, Tasky.Tasks.TaskSubmission, foreign_key: :student_id
    has_many :graded_submissions, Tasky.Tasks.TaskSubmission, foreign_key: :graded_by_id
    has_many :taught_courses, Tasky.Courses.Course, foreign_key: :teacher_id

    many_to_many :enrolled_courses, Tasky.Courses.Course,
      join_through: "course_enrollments",
      join_keys: [student_id: :id, course_id: :id]

    timestamps(type: :utc_datetime)
  end

  @valid_roles ~w(admin teacher student)

  @doc """
  Returns the list of valid roles.
  """
  def valid_roles, do: @valid_roles

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  @doc """
  A user changeset for registration that includes role.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email. Defaults to `true`.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :role])
    |> validate_email(opts)
    |> validate_role()
  end

  defp validate_role(changeset) do
    changeset
    |> validate_inclusion(:role, @valid_roles,
      message: "must be one of: #{Enum.join(@valid_roles, ", ")}"
    )
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Tasky.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end
end
