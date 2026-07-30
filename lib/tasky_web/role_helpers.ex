defmodule TaskyWeb.RoleHelpers do
  @moduledoc """
  Presentation helpers for user roles (labels and select options).
  Authorization checks live in `Tasky.Policy` / `Tasky.Accounts.Scope`.
  """

  @doc "Returns a human-readable role name."
  def role_name("admin"), do: "Admin"
  def role_name("teacher"), do: "Teacher"
  def role_name("student"), do: "Student"
  def role_name(_), do: "Unknown"

  @doc "Returns a list of role options suitable for a select input."
  def role_options do
    [
      {"Admin", "admin"},
      {"Teacher", "teacher"},
      {"Student", "student"}
    ]
  end
end
