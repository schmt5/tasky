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
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true

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

  @doc """
  Returns the list of valid roles.
  """
  def valid_roles, do: ["admin", "teacher", "student"]

  @doc """
  A user changeset for registration.

  Casts email, password, firstname, lastname, is_teacher, and class_id.
  Validates email and password, and sets the role based on is_teacher.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password, :firstname, :lastname, :is_teacher, :class_id])
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
    |> validate_password(opts)
    |> validate_role()
    |> foreign_key_constraint(:class_id)
  end

  @doc """
  A user changeset for changing the password.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "stimmt nicht überein")
    |> validate_password(opts)
  end

  @doc """
  A user changeset for changing the email.

  It requires the email to change otherwise an error is added.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
    |> case do
      %{changes: %{email: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :email, "hat sich nicht geändert")
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    change(user, confirmed_at: DateTime.utc_now(:second))
  end

  @doc """
  A user changeset for changing the profile (firstname and lastname).
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
  A user changeset for admin editing (firstname, lastname, email).
  Unlike `email_changeset/3`, it does not error when the email is unchanged.
  """
  def admin_update_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:firstname, :lastname, :email])
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
  end

  @doc """
  A user changeset for changing the Tally API key.
  """
  def tally_api_key_changeset(user, attrs) do
    user
    |> cast(attrs, [:tally_api_key])
    |> validate_required([:tally_api_key], message: "darf nicht leer sein")
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Tasky.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  defp validate_email(changeset, opts) do
    changeset
    |> validate_required([:email], message: "darf nicht leer sein")
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/,
      message: "muss ein @-Zeichen enthalten und darf keine Leerzeichen haben"
    )
    |> validate_length(:email, max: 160, message: "darf maximal 160 Zeichen lang sein")
    |> maybe_validate_unique_email(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password], message: "darf nicht leer sein")
    |> validate_length(:password,
      min: 8,
      max: 72,
      message: "muss zwischen 8 und 72 Zeichen lang sein"
    )
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> validate_length(:password,
        max: 72,
        count: :bytes,
        message: "darf maximal 72 Bytes lang sein"
      )
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  defp maybe_validate_unique_email(changeset, opts) do
    if Keyword.get(opts, :validate_email, true) do
      changeset
      |> unsafe_validate_unique(:email, Tasky.Repo)
      |> unique_constraint(:email)
    else
      changeset
    end
  end

  defp transform_is_teacher_to_role(changeset) do
    case get_change(changeset, :is_teacher) do
      true -> put_change(changeset, :role, "teacher")
      false -> put_change(changeset, :role, "student")
      nil -> changeset
    end
  end

  defp validate_role(changeset) do
    validate_inclusion(changeset, :role, valid_roles())
  end
end
