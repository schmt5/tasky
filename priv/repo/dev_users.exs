# Local dev logins: one admin and one teacher in their own organization.
# Run with: mix run priv/repo/dev_users.exs
#
# Idempotent — existing accounts are left alone. Dev only; the password is the
# same throwaway one the demo script uses.

alias Tasky.{Accounts, Organizations, Repo}
alias Tasky.Accounts.{Scope, User}

password = "password123456"

admin =
  Accounts.get_user_by_email("admin@tasky.test") ||
    %User{}
    |> User.registration_changeset(%{
      email: "admin@tasky.test",
      password: password,
      firstname: "Ada",
      lastname: "Admin"
    })
    |> Ecto.Changeset.put_change(:role, "admin")
    |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
    |> Repo.insert!()

org =
  Repo.get_by(Organizations.Organization, name: "Dev-Schule") ||
    elem(Organizations.create_organization(Scope.for_user(admin), %{name: "Dev-Schule"}), 1)

teacher =
  Accounts.get_user_by_email("lehrperson@tasky.test") ||
    elem(
      Accounts.register_user(
        %{
          email: "lehrperson@tasky.test",
          password: password,
          firstname: "Lena",
          lastname: "Lehrerin"
        },
        {:organization, org}
      ),
      1
    )

IO.puts("""
Dev logins (password: #{password}):
  admin       #{admin.email}
  teacher     #{teacher.email} (#{org.name})
""")
