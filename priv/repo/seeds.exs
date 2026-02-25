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
alias Tasky.Accounts.User
alias Tasky.Courses
alias Tasky.Courses.Course
alias Tasky.Tasks.Task

# Clear existing data
Repo.delete_all(Task)
Repo.delete_all(Course)
Repo.delete_all(User)

IO.puts("Creating users...")

# Create a teacher
{:ok, teacher} =
  Accounts.register_user(%{
    email: "teacher@example.com",
    role: "teacher"
  })

teacher = Repo.get!(User, teacher.id)
IO.puts("Created teacher: #{teacher.email}")

# Create students
{:ok, student1} =
  Accounts.register_user(%{
    email: "student1@example.com",
    role: "student"
  })

student1 = Repo.get!(User, student1.id)
IO.puts("Created student: #{student1.email}")

{:ok, student2} =
  Accounts.register_user(%{
    email: "student2@example.com",
    role: "student"
  })

student2 = Repo.get!(User, student2.id)
IO.puts("Created student: #{student2.email}")

{:ok, student3} =
  Accounts.register_user(%{
    email: "student3@example.com",
    role: "student"
  })

student3 = Repo.get!(User, student3.id)
IO.puts("Created student: #{student3.email}")

# Create an admin
{:ok, admin} =
  Accounts.register_user(%{
    email: "admin@example.com",
    role: "admin"
  })

admin = Repo.get!(User, admin.id)
IO.puts("Created admin: #{admin.email}")

IO.puts("\nCreating courses...")

# Create courses
scope = %Accounts.Scope{user: teacher}

{:ok, course1} =
  Courses.create_course(scope, %{
    name: "Introduction to Programming",
    description: "Learn the basics of programming with hands-on exercises and projects."
  })

IO.puts("Created course: #{course1.name}")

{:ok, course2} =
  Courses.create_course(scope, %{
    name: "Web Development Fundamentals",
    description: "Master HTML, CSS, and JavaScript to build modern web applications."
  })

IO.puts("Created course: #{course2.name}")

{:ok, course3} =
  Courses.create_course(scope, %{
    name: "Database Design",
    description: "Learn how to design and implement efficient database systems."
  })

IO.puts("Created course: #{course3.name}")

IO.puts("\nCreating tasks for courses...")

# Create tasks for course 1
Repo.insert!(%Task{
  name: "Hello World Program",
  link: "https://example.com/task1",
  position: 1,
  status: "published",
  user_id: teacher.id,
  course_id: course1.id
})

Repo.insert!(%Task{
  name: "Variables and Data Types",
  link: "https://example.com/task2",
  position: 2,
  status: "published",
  user_id: teacher.id,
  course_id: course1.id
})

Repo.insert!(%Task{
  name: "Control Flow",
  link: "https://example.com/task3",
  position: 3,
  status: "draft",
  user_id: teacher.id,
  course_id: course1.id
})

IO.puts("Created 3 tasks for #{course1.name}")

# Create tasks for course 2
Repo.insert!(%Task{
  name: "HTML Basics",
  link: "https://example.com/html-basics",
  position: 1,
  status: "published",
  user_id: teacher.id,
  course_id: course2.id
})

Repo.insert!(%Task{
  name: "CSS Styling",
  link: "https://example.com/css-styling",
  position: 2,
  status: "published",
  user_id: teacher.id,
  course_id: course2.id
})

Repo.insert!(%Task{
  name: "JavaScript Fundamentals",
  link: "https://example.com/js-fundamentals",
  position: 3,
  status: "published",
  user_id: teacher.id,
  course_id: course2.id
})

Repo.insert!(%Task{
  name: "Responsive Design",
  link: "https://example.com/responsive",
  position: 4,
  status: "archived",
  user_id: teacher.id,
  course_id: course2.id
})

IO.puts("Created 4 tasks for #{course2.name}")

# Create tasks for course 3
Repo.insert!(%Task{
  name: "Database Normalization",
  link: "https://example.com/normalization",
  position: 1,
  status: "published",
  user_id: teacher.id,
  course_id: course3.id
})

Repo.insert!(%Task{
  name: "SQL Queries",
  link: "https://example.com/sql",
  position: 2,
  status: "published",
  user_id: teacher.id,
  course_id: course3.id
})

IO.puts("Created 2 tasks for #{course3.name}")

IO.puts("\nEnrolling students in courses...")

# Enroll students in courses
{:ok, _} = Courses.enroll_student(course1.id, student1.id)
{:ok, _} = Courses.enroll_student(course1.id, student2.id)
{:ok, _} = Courses.enroll_student(course2.id, student1.id)
{:ok, _} = Courses.enroll_student(course2.id, student3.id)
{:ok, _} = Courses.enroll_student(course3.id, student2.id)
{:ok, _} = Courses.enroll_student(course3.id, student3.id)

IO.puts("Student1 enrolled in: #{course1.name}, #{course2.name}")
IO.puts("Student2 enrolled in: #{course1.name}, #{course3.name}")
IO.puts("Student3 enrolled in: #{course2.name}, #{course3.name}")

IO.puts("\n✓ Seed data created successfully!")
IO.puts("\nYou can log in with:")
IO.puts("  Teacher: teacher@example.com")
IO.puts("  Student1: student1@example.com")
IO.puts("  Student2: student2@example.com")
IO.puts("  Student3: student3@example.com")
IO.puts("  Admin: admin@example.com")
