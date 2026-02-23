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
alias Tasky.Accounts

# Check if we already have users to avoid duplicates
existing_users = Repo.aggregate(Accounts.User, :count)

if existing_users == 0 do
  IO.puts("Creating seed users with different roles...")

  # Create an admin user
  {:ok, admin} =
    Accounts.register_user(%{
      email: "admin@example.com",
      password: "adminpassword123",
      role: "admin"
    })

  IO.puts("✓ Created admin user: #{admin.email}")

  # Create a teacher user
  {:ok, teacher} =
    Accounts.register_user(%{
      email: "teacher@example.com",
      password: "teacherpassword123",
      role: "teacher"
    })

  IO.puts("✓ Created teacher user: #{teacher.email}")

  # Create multiple student users
  {:ok, student1} =
    Accounts.register_user(%{
      email: "student1@example.com",
      password: "studentpassword123",
      role: "student"
    })

  IO.puts("✓ Created student user: #{student1.email}")

  {:ok, student2} =
    Accounts.register_user(%{
      email: "student2@example.com",
      password: "studentpassword123",
      role: "student"
    })

  IO.puts("✓ Created student user: #{student2.email}")

  IO.puts("\n✅ Seed data created successfully!")
  IO.puts("\nYou can log in with:")
  IO.puts("  Admin:    admin@example.com / adminpassword123")
  IO.puts("  Teacher:  teacher@example.com / teacherpassword123")
  IO.puts("  Student:  student1@example.com / studentpassword123")
  IO.puts("  Student:  student2@example.com / studentpassword123")
else
  IO.puts("⚠️  Database already contains #{existing_users} user(s). Skipping seed data.")
end
