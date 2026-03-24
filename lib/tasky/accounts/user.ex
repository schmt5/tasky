defmodule Tasky.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :firstname, :string
    field :lastname, :string
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true
    field :role, :string, default: "student"
    field :tally_api_key, :string

    # Virtual fields for UI representation
    field :is_teacher, :boolean, virtual: true, default: false

    belongs_to :class, Tasky.Classes.Class

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
    |> cast(attrs, [:email, :firstname, :lastname, :is_teacher, :class_id])
    |> transform_is_teacher_to_role()
    |> validate_required([:firstname, :lastname], message: "darf nicht leer sein")
    |> validate_length(:firstname,
      min: 1,
      max: 100,
      message: "muss zwischen 1 und 100 Zeichen lang sein"
    )
    |> validate_length(:lastname,
      min: 1,
      max: 100,
      message: "muss zwischen 1 und 100 Zeichen lang sein"
    )
    |> validate_email(opts)
    |> validate_role()
    |> foreign_key_constraint(:class_id)
  end

  # Transform virtual field is_teacher to role field
  defp transform_is_teacher_to_role(changeset) do
    case get_change(changeset, :is_teacher) do
      true ->
        put_change(changeset, :role, "teacher")

      false ->
        put_change(changeset, :role, "student")

      nil ->
        # If is_teacher is not provided, default to student
        put_change(changeset, :role, "student")
    end
  end

  @doc """
  A user changeset for updating profile information (firstname and lastname).
  """
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:firstname, :lastname])
    |> validate_required([:firstname, :lastname], message: "darf nicht leer sein")
    |> validate_length(:firstname,
      min: 1,
      max: 100,
      message: "muss zwischen 1 und 100 Zeichen lang sein"
    )
    |> validate_length(:lastname,
      min: 1,
      max: 100,
      message: "muss zwischen 1 und 100 Zeichen lang sein"
    )
  end

  @doc """
  A user changeset for updating the Tally API key.
  """
  def tally_api_key_changeset(user, attrs) do
    user
    |> cast(attrs, [:tally_api_key])
    |> validate_tally_api_key()
  end

  defp validate_tally_api_key(changeset) do
    case get_change(changeset, :tally_api_key) do
      nil ->
        # No change, valid
        changeset

      "" ->
        # Empty string not allowed
        add_error(changeset, :tally_api_key, "darf nicht leer sein")

      value when is_binary(value) ->
        # Trim and validate length
        changeset
        |> put_change(:tally_api_key, String.trim(value))
        |> validate_length(:tally_api_key,
          min: 1,
          max: 255,
          message: "muss zwischen 1 und 255 Zeichen lang sein"
        )
    end
  end

  defp validate_role(changeset) do
    changeset
    |> validate_inclusion(:role, @valid_roles,
      message: "muss einer der folgenden Werte sein: #{Enum.join(@valid_roles, ", ")}"
    )
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email], message: "darf nicht leer sein")
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "muss ein @-Zeichen enthalten und darf keine Leerzeichen haben"
      )
      |> validate_length(:email, max: 160, message: "darf maximal 160 Zeichen lang sein")

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
      add_error(changeset, :email, "hat sich nicht geändert")
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
