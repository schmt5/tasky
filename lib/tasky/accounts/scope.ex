defmodule Tasky.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `Tasky.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use as authorization, or to
  ensure specific code paths can only be access for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias Tasky.Accounts.User

  defstruct user: nil

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil

  @doc """
  Returns true if the scope has an admin role.
  """
  def admin?(%__MODULE__{user: %User{role: "admin"}}), do: true
  def admin?(_), do: false

  @doc """
  Returns true if the scope has a teacher role.
  """
  def teacher?(%__MODULE__{user: %User{role: "teacher"}}), do: true
  def teacher?(_), do: false

  @doc """
  Returns true if the scope has a student role.
  """
  def student?(%__MODULE__{user: %User{role: "student"}}), do: true
  def student?(_), do: false

  @doc """
  Returns true if the scope has an admin or teacher role.
  """
  def admin_or_teacher?(%__MODULE__{user: %User{role: role}}) when role in ["admin", "teacher"],
    do: true

  def admin_or_teacher?(_), do: false

  @doc """
  Returns the role of the user in the scope.
  """
  def role(%__MODULE__{user: %User{role: role}}), do: role
  def role(_), do: nil
end
