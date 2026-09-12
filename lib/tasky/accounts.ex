defmodule Tasky.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Tasky.Repo

  alias Tasky.Accounts.{User, UserNotifier, UserToken}
  alias Tasky.Classes
  alias Tasky.Courses.CourseEnrollment
  alias Tasky.Exams.ExamSubmission
  alias Tasky.Tasks.TaskSubmission

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc "Gets a single user with the class association loaded."
  def get_user_with_class!(id),
    do: Repo.get!(User, id) |> Repo.preload([[class: :organization], :organization])

  ## User registration

  @doc """
  Registers a user against an invitation.

  There is no open registration: the invitation decides the role, and it is
  resolved server-side from the link the visitor arrived with. Exactly two forms
  exist, and there is deliberately no third clause — a request without a valid
  invitation cannot produce an account at all.

    * `{:class, %Class{}}` — from `/users/register?class=<slug>`. Creates a
      **student** in that class. Their organization is derived from the class, so
      `organization_id` stays `nil`.

    * `{:organization, %Organization{}}` — from `/users/register?invite=<token>`.
      Creates a **teacher** in that organization, with no class.

  Because the role never comes from parameters, registering into a foreign
  organization is structurally impossible rather than validated.

  The user is automatically confirmed upon registration.

  ## Examples

      iex> register_user(attrs, {:class, class})
      {:ok, %User{role: "student"}}

      iex> register_user(%{}, {:organization, org})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs, invitation) do
    %User{}
    |> User.registration_changeset(attrs)
    |> apply_invitation(invitation)
    |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
    |> Repo.insert()
  end

  defp apply_invitation(changeset, {:class, %Tasky.Classes.Class{} = class}) do
    changeset
    |> Ecto.Changeset.put_change(:role, "student")
    |> Ecto.Changeset.put_change(:class_id, class.id)
    |> Ecto.Changeset.put_change(:organization_id, nil)
  end

  defp apply_invitation(changeset, {:organization, %Tasky.Organizations.Organization{} = org}) do
    changeset
    |> Ecto.Changeset.put_change(:role, "teacher")
    |> Ecto.Changeset.put_change(:organization_id, org.id)
    |> Ecto.Changeset.put_change(:class_id, nil)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user registration changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(user, attrs \\ %{}, opts \\ []) do
    User.registration_changeset(user, attrs, opts)
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Tasky.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user profile (firstname and lastname).

  ## Examples

      iex> change_user_profile(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_profile(user, attrs \\ %{}) do
    User.profile_changeset(user, attrs)
  end

  @doc """
  Updates the user profile (firstname and lastname).

  ## Examples

      iex> update_user_profile(user, %{firstname: "John", lastname: "Doe"})
      {:ok, %User{}}

      iex> update_user_profile(user, %{firstname: ""})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_profile(user, attrs) do
    user
    |> change_user_profile(attrs)
    |> Repo.update()
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Updates the user email directly without token verification.
  """
  def update_user_email_directly(user, attrs) do
    user
    |> User.email_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Resets a user's password (admin action) and invalidates every session the
  user has open.

  Returns the deleted tokens alongside the user: a session token is only half
  revoked once its row is gone — a LiveView socket that is already connected
  keeps running until it reconnects — so the web layer still has to disconnect
  them (`TaskyWeb.UserAuth.disconnect_sessions/1`).

  ## Examples

      iex> admin_reset_password(user, "new_password123")
      {:ok, {%User{}, [%UserToken{}]}}

      iex> admin_reset_password(user, "short")
      {:error, %Ecto.Changeset{}}

  """
  def admin_reset_password(scope, user, new_password) do
    with :ok <- Tasky.Policy.authorize_admin(scope) do
      do_admin_reset_password(user, new_password)
    end
  end

  defp do_admin_reset_password(user, new_password) do
    Repo.transaction(fn ->
      case user |> User.password_changeset(%{password: new_password}) |> Repo.update() do
        {:ok, updated} ->
          {_count, tokens} =
            Repo.delete_all(
              from(t in UserToken.by_user_and_contexts_query(user, :all), select: t)
            )

          {updated, tokens}

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Role management

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user role.

  ## Examples

      iex> change_user_role(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_role(user, attrs \\ %{}) do
    user
    |> Ecto.Changeset.cast(attrs, [:role])
    |> Ecto.Changeset.validate_inclusion(:role, User.valid_roles())
  end

  @doc """
  Updates the user role.

  ## Examples

      iex> update_user_role(user, %{role: "teacher"})
      {:ok, %User{}}

      iex> update_user_role(user, %{role: "invalid"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_role(user, attrs) do
    user
    |> change_user_role(attrs)
    |> Repo.update()
  end

  @doc """
  Returns all users with a specific role.

  ## Examples

      iex> list_users_by_role("teacher")
      [%User{}, ...]

  """
  def list_users_by_role(role) when role in ["admin", "teacher", "student"] do
    Repo.all(from u in User, where: u.role == ^role, order_by: [asc: u.email])
  end

  @doc """
  Returns all users grouped by role.

  ## Examples

      iex> list_all_users_grouped_by_role()
      %{"admin" => [...], "teacher" => [...], "student" => [...]}

  """
  def list_all_users_grouped_by_role do
    User.valid_roles()
    |> Enum.map(fn role -> {role, list_users_by_role(role)} end)
    |> Enum.into(%{})
  end

  @doc """
  Returns users with their class preloaded, ordered by lastname then firstname.

  Accepts an optional keyword list of filters:
    * `:role` — "admin" | "teacher" | "student"
    * `:class_id` — integer class id, or `:none` for users without a class
  """
  def list_users(filters \\ []) do
    base =
      from(u in User,
        order_by: [asc: u.lastname, asc: u.firstname],
        preload: [[class: :organization], :organization]
      )

    filters
    |> Enum.reduce(base, &apply_user_filter/2)
    |> Repo.all()
  end

  defp apply_user_filter({:role, role}, query) when role in ["admin", "teacher", "student"] do
    from u in query, where: u.role == ^role
  end

  defp apply_user_filter({:class_id, :none}, query) do
    from u in query, where: is_nil(u.class_id)
  end

  defp apply_user_filter({:class_id, id}, query) when is_integer(id) do
    from u in query, where: u.class_id == ^id
  end

  defp apply_user_filter({:search, term}, query) when is_binary(term) do
    trimmed = String.trim(term)

    if trimmed == "" do
      query
    else
      pattern = "%" <> String.replace(trimmed, ["%", "_"], &("\\" <> &1)) <> "%"

      from u in query,
        where:
          like(u.firstname, ^pattern) or
            like(u.lastname, ^pattern) or
            like(u.email, ^pattern)
    end
  end

  defp apply_user_filter(_, query), do: query

  ## Student directory (organization-scoped)

  @doc """
  Lists the students the scope may see, newest filters applied.

  The organization-scoped counterpart to `list_users/1`: a teacher sees the
  students of their own organization (derived through `classes.organization_id`),
  an admin sees all of them, and a teacher without an organization sees none.
  Accepts the same `:search` and `:class_id` filters; `:role` is meaningless here
  because every row is a student.
  """
  def list_students(scope, filters \\ []) do
    base =
      scope
      |> Tasky.Organizations.visible_students_query()
      |> order_by([u], asc: u.lastname, asc: u.firstname)
      |> preload([[class: :organization], :organization])

    filters
    |> Enum.reduce(base, &apply_user_filter/2)
    |> Repo.all()
  end

  @doc """
  Gets a single student the scope may see, with class and organization loaded.

  Raises `Ecto.NoResultsError` for a student of another organization, so a
  foreign student is indistinguishable from a missing one (same convention as
  `Tasky.Classes.get_class!/2`).
  """
  def get_student!(scope, id) do
    scope
    |> Tasky.Organizations.visible_students_query()
    |> where([u], u.id == ^id)
    |> preload([[class: :organization], :organization])
    |> Repo.one!()
  end

  @doc """
  Updates a student's profile on behalf of a teacher or admin.

  Two authorization steps, and both are needed:

    * the *student* must be visible to the scope, and
    * the *target class* must be too — otherwise a teacher could hand a student
      to another organization by posting a foreign `class_id`, which would also
      remove them from their own sight.

  `organization_id` is dropped rather than validated: a student's organization is
  always derived from their class, so there is no legitimate value for it here.
  """
  def update_student(scope, %User{} = student, attrs) do
    attrs = Map.drop(attrs, ["organization_id", :organization_id])

    with :ok <- authorize_student(scope, student),
         :ok <- authorize_target_class(scope, attrs) do
      student
      |> User.admin_update_changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Sets a new password for a student, on behalf of a teacher or admin.

  Production sends no mail (`Swoosh.Adapters.Local`), so this is the only way a
  student who forgot their password gets back in. Like `admin_reset_password/3`
  it invalidates every existing session of that student.
  """
  def reset_student_password(scope, %User{} = student, new_password) do
    with :ok <- authorize_student(scope, student) do
      do_admin_reset_password(student, new_password)
    end
  end

  @doc """
  What hangs off a learner's account, for the deletion confirmation.

  Deliberately three separate numbers rather than one total, because they do
  *not* share a fate — see `delete_student/2`. A duplicate account shows zero
  everywhere, which is exactly what the teacher needs to see before confirming.
  """
  def student_data_summary(scope, %User{} = student) do
    with :ok <- authorize_student(scope, student) do
      {:ok,
       %{
         task_submissions: count_rows(where(TaskSubmission, [s], s.student_id == ^student.id)),
         exam_submissions: count_rows(where(ExamSubmission, [s], s.user_id == ^student.id)),
         course_enrollments: count_rows(where(CourseEnrollment, [e], e.student_id == ^student.id))
       }}
    end
  end

  defp count_rows(query), do: Repo.aggregate(query, :count)

  @doc """
  Deletes a learner's account for good, on behalf of a teacher or admin.

  The use case is a learner who registered twice: one of the two accounts has
  to go. `authorize_student/2` is what makes this safe to expose to teachers —
  it refuses anything that is not a *student* visible to the scope, so the
  `courses.teacher_id` / `exams.teacher_id` cascades (which would take
  colleagues' whole courses and every participant's exam with them) are
  unreachable from here, and nobody can delete themselves.

  What the row's disappearance does to the rest of the data is decided by the
  foreign keys, and the three outcomes are all intentional:

    * **gone** — sessions, course enrolments, and the learner's learning-unit
      submissions with their teacher feedback (`:delete_all`),
    * **kept, anonymised** — exam submissions (`:nilify_all`); the copied
      firstname/lastname/email on the row are what keep a graded exam gradable,
      which is the whole reason that FK nilifies. Anonymous course feedback
      survives the same way.

  The stored bytes of those cascaded submissions are nobody's job but ours —
  no FK reaches into storage — so they are collected *before* the delete and
  cleared after it, the same shape as `Tasky.Exams.delete_exam/2`. Exam
  submission files stay, because their rows do.
  """
  def delete_student(scope, %User{} = student) do
    with :ok <- authorize_student(scope, student) do
      submission_dirs =
        TaskSubmission
        |> where([s], s.student_id == ^student.id)
        |> select([s], {s.task_id, s.id})
        |> Repo.all()

      case Repo.delete(student) do
        {:ok, deleted} ->
          # After the commit, and never inside it: a storage hiccup must not
          # roll back a deletion the teacher already confirmed.
          Tasky.Uploads.delete_task_submission_dirs(submission_dirs)
          {:ok, deleted}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  defp authorize_student(scope, %User{role: "student", id: id}) do
    visible? =
      scope
      |> Tasky.Organizations.visible_students_query()
      |> where([u], u.id == ^id)
      |> Repo.exists?()

    if visible?, do: :ok, else: {:error, :unauthorized}
  end

  defp authorize_student(_scope, %User{}), do: {:error, :unauthorized}

  # An absent `class_id` leaves the current one alone; an explicit empty one
  # clears it — which only an admin can undo, so the UI warns about it.
  defp authorize_target_class(scope, attrs) do
    case fetch_class_id(attrs) do
      :absent -> :ok
      {:ok, blank} when blank in [nil, ""] -> :ok
      {:ok, id} -> if Classes.visible?(scope, id), do: :ok, else: {:error, :unauthorized}
    end
  end

  defp fetch_class_id(attrs) do
    case Map.fetch(attrs, "class_id") do
      {:ok, value} -> {:ok, value}
      :error -> with :error <- Map.fetch(attrs, :class_id), do: :absent
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for admin editing of a user
  (firstname, lastname, email).
  """
  def change_user_admin(user, attrs \\ %{}, opts \\ []) do
    User.admin_update_changeset(user, attrs, opts)
  end

  @doc """
  Admin update of a user's firstname, lastname, and email.
  """
  def admin_update_user(scope, user, attrs) do
    with :ok <- Tasky.Policy.authorize_admin(scope) do
      user
      |> User.admin_update_changeset(attrs)
      |> Repo.update()
    end
  end
end
