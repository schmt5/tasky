# Demo Setup Script for Task Submissions
# Run with: mix run priv/repo/demo_submissions.exs

alias Tasky.{Accounts, Tasks, Repo}
alias Tasky.Accounts.Scope

IO.puts("\n🚀 Setting up Task Submission Demo...\n")

# Create users
IO.puts("Creating users...")

# `registration_changeset/3` requires firstname/lastname and does NOT cast
# `:role` — it derives it from `is_teacher`. "admin" therefore has to be set
# afterwards via `update_user_role/2`.
{:ok, teacher} =
  Accounts.register_user(%{
    email: "teacher@demo.com",
    password: "password123456",
    firstname: "Tina",
    lastname: "Lehrer",
    is_teacher: true
  })

IO.puts("✅ Created teacher: teacher@demo.com")

students =
  for i <- 1..3 do
    {:ok, student} =
      Accounts.register_user(%{
        email: "student#{i}@demo.com",
        password: "password123456",
        firstname: "Sam#{i}",
        lastname: "Schüler",
        is_teacher: false
      })

    IO.puts("✅ Created student: student#{i}@demo.com")
    student
  end

{:ok, admin} =
  Accounts.register_user(%{
    email: "admin@demo.com",
    password: "password123456",
    firstname: "Alex",
    lastname: "Admin",
    is_teacher: false
  })

{:ok, admin} = Accounts.update_user_role(admin, %{role: "admin"})

IO.puts("✅ Created admin: admin@demo.com")

# Create tasks
IO.puts("\n📝 Creating tasks...")

teacher_scope = Scope.for_user(teacher)

tasks = [
  %{
    name: "Introduction to Elixir",
    link: "https://elixir-lang.org/getting-started/introduction.html",
    status: "published",
    position: 1
  },
  %{
    name: "Phoenix Framework Basics",
    link: "https://hexdocs.pm/phoenix/overview.html",
    status: "published",
    position: 2
  },
  %{
    name: "LiveView Tutorial",
    link: "https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html",
    status: "published",
    position: 3
  },
  %{
    name: "Advanced Ecto Queries",
    link: nil,
    status: "draft",
    position: 4
  }
]

created_tasks =
  for task_attrs <- tasks do
    {:ok, task} = Tasks.create_task(teacher_scope, task_attrs)
    IO.puts("✅ Created task: #{task.name}")
    task
  end

# Create submissions with different statuses
IO.puts("\n📋 Creating submissions...")

[task1, task2, task3, _task4] = created_tasks
[student1, student2, student3] = students

# Student 1: Has completed all tasks
student1_scope = Scope.for_user(student1)

{:ok, sub1_1} = Tasks.get_or_create_submission(student1_scope, task1.id)
{:ok, sub1_1} = Tasks.update_submission_status(student1_scope, sub1_1.id, "in_progress")
{:ok, sub1_1} = Tasks.complete_task(student1_scope, sub1_1.id)
IO.puts("✅ Student1 completed: #{task1.name}")

{:ok, sub1_2} = Tasks.get_or_create_submission(student1_scope, task2.id)
{:ok, sub1_2} = Tasks.update_submission_status(student1_scope, sub1_2.id, "in_progress")
{:ok, sub1_2} = Tasks.complete_task(student1_scope, sub1_2.id)
IO.puts("✅ Student1 completed: #{task2.name}")

{:ok, sub1_3} = Tasks.get_or_create_submission(student1_scope, task3.id)
{:ok, sub1_3} = Tasks.update_submission_status(student1_scope, sub1_3.id, "in_progress")
{:ok, sub1_3} = Tasks.complete_task(student1_scope, sub1_3.id)
IO.puts("✅ Student1 completed: #{task3.name}")

# Student 2: Has one in progress, one completed
student2_scope = Scope.for_user(student2)

{:ok, sub2_1} = Tasks.get_or_create_submission(student2_scope, task1.id)
{:ok, _sub2_1} = Tasks.update_submission_status(student2_scope, sub2_1.id, "in_progress")
IO.puts("✅ Student2 in progress: #{task1.name}")

{:ok, sub2_2} = Tasks.get_or_create_submission(student2_scope, task2.id)
{:ok, sub2_2} = Tasks.update_submission_status(student2_scope, sub2_2.id, "in_progress")
{:ok, sub2_2} = Tasks.complete_task(student2_scope, sub2_2.id)
IO.puts("✅ Student2 completed: #{task2.name}")

# Student 3: Has just started viewing tasks
student3_scope = Scope.for_user(student3)

{:ok, _sub3_1} = Tasks.get_or_create_submission(student3_scope, task1.id)
IO.puts("✅ Student3 viewed: #{task1.name}")

# Teacher reviews some submissions — genehmigt, zurückgegeben und Feedback
# ohne Verdikt, damit alle drei Zustände in den Demodaten vorkommen.
IO.puts("\n⭐ Reviewing submissions...")

{:ok, _} =
  Tasks.review_submission(teacher_scope, sub1_1.id, "review_approved", %{
    feedback: "Excellent work! Your understanding of Elixir basics is very strong."
  })

IO.puts("✅ Approved Student1's #{task1.name}")

{:ok, _} =
  Tasks.review_submission(teacher_scope, sub1_2.id, "review_denied", %{
    feedback: "Bitte ergänze noch ein Beispiel zu Phoenix Contexts und reiche erneut ein."
  })

IO.puts("↩️  Sent back Student1's #{task2.name}")

{:ok, _} =
  Tasks.save_feedback(teacher_scope, sub2_2.id, %{
    feedback: "Great work! Your Phoenix implementation is solid."
  })

IO.puts("💬 Feedback on Student2's #{task2.name}")

# Print summary
IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("🎉 Demo setup complete!")
IO.puts(String.duplicate("=", 60))

IO.puts("\n📊 Summary:")
IO.puts("  • 1 Teacher: teacher@demo.com")
IO.puts("  • 3 Students: student1@demo.com, student2@demo.com, student3@demo.com")
IO.puts("  • 1 Admin: admin@demo.com")
IO.puts("  • 4 Tasks created")
IO.puts("  • Multiple submissions with different statuses")
IO.puts("  • Some submissions already graded")

IO.puts("\n🔑 Login Credentials (all passwords: password123456):")
IO.puts("  Teacher: teacher@demo.com")
IO.puts("  Student 1: student1@demo.com (3 tasks completed, 2 graded)")
IO.puts("  Student 2: student2@demo.com (1 in progress, 1 completed & graded)")
IO.puts("  Student 3: student3@demo.com (1 viewed)")
IO.puts("  Admin: admin@demo.com")

IO.puts("\n🚀 Quick Start:")
IO.puts("  1. Start server: mix phx.server")
IO.puts("  2. Visit: http://localhost:4000")
IO.puts("  3. Log in with any account above")

IO.puts("\n📍 URLs to try:")
IO.puts("  Student Dashboard: /student/my-tasks")
IO.puts("  Teacher Tasks: /tasks")
IO.puts("  Submissions: /tasks/#{task1.id}/submissions")

IO.puts("\n✨ Have fun exploring the task submission system!\n")
