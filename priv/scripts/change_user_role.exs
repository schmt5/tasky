# Script to change a user's role
#
# Usage:
#   mix run priv/scripts/change_user_role.exs <email> <role>
#
# Example:
#   mix run priv/scripts/change_user_role.exs user@example.com teacher
#
# Valid roles: admin, teacher, student

import Ecto.Query
alias Tasky.Repo
alias Tasky.Accounts.User

[email, new_role | _] = System.argv()

if is_nil(email) or is_nil(new_role) do
  IO.puts("""
  ❌ Error: Missing arguments

  Usage: mix run priv/scripts/change_user_role.exs <email> <role>

  Example:
    mix run priv/scripts/change_user_role.exs user@example.com teacher

  Valid roles: admin, teacher, student
  """)

  System.halt(1)
end

unless new_role in ["admin", "teacher", "student"] do
  IO.puts("""
  ❌ Error: Invalid role "#{new_role}"

  Valid roles are: admin, teacher, student
  """)

  System.halt(1)
end

case Repo.get_by(User, email: email) do
  nil ->
    IO.puts("❌ Error: User with email '#{email}' not found")
    System.halt(1)

  user ->
    old_role = user.role

    case Repo.update(Ecto.Changeset.change(user, role: new_role)) do
      {:ok, updated_user} ->
        IO.puts("""
        ✅ Successfully updated user role!

        Email: #{updated_user.email}
        Old role: #{old_role}
        New role: #{updated_user.role}
        """)

      {:error, changeset} ->
        IO.puts("❌ Error updating user:")
        IO.inspect(changeset.errors)
        System.halt(1)
    end
end
