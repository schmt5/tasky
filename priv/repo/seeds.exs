# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Tasky.Repo.insert!(%Tasky.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

import Ecto.Query
alias Tasky.Repo
alias Tasky.Accounts.User

# Check if we already have users to avoid duplicates
existing_users = Repo.aggregate(User, :count)

if existing_users == 0 do
  IO.puts("Creating seed users with different roles...")

  # Create an admin user
  {:ok, admin} =
    Accounts.register_user(%{
      email: "admin@example.com",
      role: "admin"
    })

  # Confirm the admin user
  admin = Repo.update!(Ecto.Changeset.change(admin, confirmed_at: DateTime.utc_now()))

  IO.puts("✓ Created admin user: #{admin.email}")

  # Create a teacher user
  {:ok, teacher} =
    Accounts.register_user(%{
      email: "teacher@example.com",
      role: "teacher"
    })

  # Confirm the teacher user
  teacher = Repo.update!(Ecto.Changeset.change(teacher, confirmed_at: DateTime.utc_now()))

  IO.puts("✓ Created teacher user: #{teacher.email}")

  # Create multiple student users
  {:ok, student1} =
    Accounts.register_user(%{
      email: "student1@example.com",
      role: "student"
    })

  # Confirm the student user
  student1 = Repo.update!(Ecto.Changeset.change(student1, confirmed_at: DateTime.utc_now()))

  IO.puts("✓ Created student user: #{student1.email}")

  {:ok, student2} =
    Accounts.register_user(%{
      email: "student2@example.com",
      role: "student"
    })

  # Confirm the student user
  student2 = Repo.update!(Ecto.Changeset.change(student2, confirmed_at: DateTime.utc_now()))

  IO.puts("✓ Created student user: #{student2.email}")

  IO.puts("\n✅ Seed data created successfully!")
  IO.puts("\nYou can log in with magic links using these emails:")
  IO.puts("  Admin:    admin@example.com")
  IO.puts("  Teacher:  teacher@example.com")
  IO.puts("  Student:  student1@example.com")
  IO.puts("  Student:  student2@example.com")
else
  IO.puts("⚠️  Database already contains #{existing_users} user(s). Skipping seed data.")
end
