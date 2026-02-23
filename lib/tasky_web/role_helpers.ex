defmodule TaskyWeb.RoleHelpers do
  @moduledoc """
  Helper functions for role-based authorization in templates and LiveViews.

  These functions provide a convenient way to check user roles and
  permissions throughout the application.
  """

  alias Tasky.Accounts.Scope

  @doc """
  Returns true if the current scope has an admin role.

  ## Examples

      iex> admin?(%Scope{user: %User{role: "admin"}})
      true

      iex> admin?(%Scope{user: %User{role: "teacher"}})
      false

      iex> admin?(nil)
      false
  """
  def admin?(scope), do: Scope.admin?(scope)

  @doc """
  Returns true if the current scope has a teacher role.

  ## Examples

      iex> teacher?(%Scope{user: %User{role: "teacher"}})
      true

      iex> teacher?(%Scope{user: %User{role: "student"}})
      false
  """
  def teacher?(scope), do: Scope.teacher?(scope)

  @doc """
  Returns true if the current scope has a student role.

  ## Examples

      iex> student?(%Scope{user: %User{role: "student"}})
      true

      iex> student?(%Scope{user: %User{role: "admin"}})
      false
  """
  def student?(scope), do: Scope.student?(scope)

  @doc """
  Returns true if the current scope has an admin or teacher role.

  ## Examples

      iex> admin_or_teacher?(%Scope{user: %User{role: "admin"}})
      true

      iex> admin_or_teacher?(%Scope{user: %User{role: "teacher"}})
      true

      iex> admin_or_teacher?(%Scope{user: %User{role: "student"}})
      false
  """
  def admin_or_teacher?(scope), do: Scope.admin_or_teacher?(scope)

  @doc """
  Returns the role of the user in the scope.

  ## Examples

      iex> role(%Scope{user: %User{role: "teacher"}})
      "teacher"

      iex> role(nil)
      nil
  """
  def role(scope), do: Scope.role(scope)

  @doc """
  Returns a human-readable role name.

  ## Examples

      iex> role_name("admin")
      "Admin"

      iex> role_name("teacher")
      "Teacher"

      iex> role_name("student")
      "Student"
  """
  def role_name("admin"), do: "Admin"
  def role_name("teacher"), do: "Teacher"
  def role_name("student"), do: "Student"
  def role_name(_), do: "Unknown"

  @doc """
  Returns a list of all valid roles.

  ## Examples

      iex> valid_roles()
      ["admin", "teacher", "student"]
  """
  def valid_roles, do: Tasky.Accounts.User.valid_roles()

  @doc """
  Returns a list of role options suitable for a select input.

  ## Examples

      iex> role_options()
      [{"Admin", "admin"}, {"Teacher", "teacher"}, {"Student", "student"}]
  """
  def role_options do
    [
      {"Admin", "admin"},
      {"Teacher", "teacher"},
      {"Student", "student"}
    ]
  end
end
