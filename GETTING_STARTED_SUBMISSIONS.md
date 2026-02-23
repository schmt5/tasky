# Getting Started with Task Submissions

## 🎯 Quick Overview

The task submission system is **complete and ready to use**! This guide will get you up and running in minutes.

## ✅ What's Included

- **Student Interface** - View tasks, track progress, see grades
- **Teacher Interface** - Create tasks, view submissions, grade work
- **Beautiful UI** - Modern, responsive, intuitive design
- **Full Authorization** - Role-based access control
- **Comprehensive Tests** - All features tested

## 🚀 Quick Start (5 Minutes)

### 1. Ensure Database is Ready

```bash
cd tasky
mix ecto.migrate
```

### 2. Run the Demo Setup Script

```bash
mix run priv/repo/demo_submissions.exs
```

This creates:
- 1 teacher (teacher@demo.com)
- 3 students (student1@demo.com, student2@demo.com, student3@demo.com)
- 1 admin (admin@demo.com)
- 4 sample tasks
- Multiple submissions at different stages
- Some graded submissions

**All passwords:** `password123456`

### 3. Start the Server

```bash
mix phx.server
```

Visit: http://localhost:4000

### 4. Try It Out!

#### As a Student:
1. Log in with `student1@demo.com` / `password123456`
2. Click "My Tasks" in the navigation
3. See your completed tasks with grades!
4. Click "View" on any task to see details

#### As a Teacher:
1. Log in with `teacher@demo.com` / `password123456`
2. Click "Tasks" in the navigation
3. Click any task to see statistics
4. Click "View Submissions" to see all students
5. Click "Grade" on an ungraded submission
6. Enter points and feedback, then save

## 📍 Key URLs

### For Students
- **My Tasks List**: `/student/my-tasks`
- **Task Detail**: `/student/tasks/:id`

### For Teachers
- **Tasks List**: `/tasks`
- **Task Detail**: `/tasks/:id`
- **Submissions List**: `/tasks/:id/submissions`
- **Grade Form**: `/tasks/:task_id/grade/:id`

### Common
- **Login**: `/users/log-in`
- **Register**: `/users/register`
- **Settings**: `/users/settings`

## 🎓 How It Works

### Student Workflow

```
1. View "My Tasks" list
   ↓
2. Click "View" on a task
   ↓
3. Click "Start Task" (status → In Progress)
   ↓
4. Do the work
   ↓
5. Click "Mark as Complete" (status → Completed)
   ↓
6. Wait for teacher to grade
   ↓
7. See your grade and feedback! 🎉
```

### Teacher Workflow

```
1. View "Tasks" list
   ↓
2. Click a task to see details
   ↓
3. Click "View Submissions"
   ↓
4. Click "Grade" next to a completed submission
   ↓
5. Enter points (0-100) and optional feedback
   ↓
6. Click "Save Grade"
   ↓
7. Student can now see their grade!
```

## 🎨 Features

### For Students
✅ View all assigned tasks in one place
✅ Track task status (Not Started, In Progress, Completed)
✅ See grades immediately when available
✅ Read teacher feedback
✅ Access task links and resources
✅ View completion and grading dates

### For Teachers
✅ Create and manage tasks
✅ See all student submissions
✅ Track who has completed tasks
✅ Grade with points (0-100) and feedback
✅ Update grades if needed
✅ View statistics (total, completed, graded, pending)
✅ Know exactly who needs grading

### Technical
✅ Auto-creates submissions (no manual setup)
✅ Real-time status updates
✅ Role-based authorization
✅ Beautiful, responsive design
✅ Comprehensive test coverage
✅ Production-ready code

## 📚 Documentation

### For End Users
- **[USER_GUIDE.md](USER_GUIDE.md)** - Complete user documentation
  - Student guide with screenshots
  - Teacher guide with workflows
  - Visual reference diagrams
  - FAQ and troubleshooting

### For Developers
- **[UI_IMPLEMENTATION_COMPLETE.md](UI_IMPLEMENTATION_COMPLETE.md)** - Implementation summary
  - Files created
  - Routes added
  - Design features
  - Test coverage

- **[SUBMISSION_UI_COMPLETE.md](SUBMISSION_UI_COMPLETE.md)** - Technical details
  - Architecture overview
  - Code organization
  - Best practices
  - Enhancement ideas

- **[TASK_SUBMISSIONS_QUICKSTART.md](TASK_SUBMISSIONS_QUICKSTART.md)** - Backend API
  - Context functions
  - Usage examples
  - Testing guide

## 🧪 Running Tests

```bash
# All submission UI tests
mix test test/tasky_web/live/student/
mix test test/tasky_web/live/teacher/

# Specific test files
mix test test/tasky_web/live/student/task_live_test.exs
mix test test/tasky_web/live/student/my_tasks_live_test.exs
mix test test/tasky_web/live/teacher/submissions_live_test.exs
mix test test/tasky_web/live/teacher/grade_live_test.exs

# Run all tests
mix test
```

## 🔧 Manual Setup (Without Demo Script)

If you prefer to set up manually:

### 1. Create a Teacher

```elixir
# In IEx (iex -S mix phx.server)
{:ok, teacher} = Tasky.Accounts.register_user(%{
  email: "teacher@example.com",
  password: "securepassword123",
  role: "teacher"
})
```

### 2. Create a Student

```elixir
{:ok, student} = Tasky.Accounts.register_user(%{
  email: "student@example.com",
  password: "securepassword123",
  role: "student"
})
```

### 3. Create a Task (as Teacher)

```elixir
teacher_scope = Tasky.Accounts.Scope.for_user(teacher)

{:ok, task} = Tasky.Tasks.create_task(teacher_scope, %{
  name: "My First Assignment",
  link: "https://example.com/instructions",
  status: "published",
  position: 1
})
```

### 4. Student Completes Task

```elixir
student_scope = Tasky.Accounts.Scope.for_user(student)

# Get or create submission (happens automatically when viewing task)
{:ok, submission} = Tasky.Tasks.get_or_create_submission(
  student_scope,
  task.id
)

# Complete the task
{:ok, submission} = Tasky.Tasks.complete_task(
  student_scope,
  submission.id
)
```

### 5. Teacher Grades

```elixir
{:ok, _} = Tasky.Tasks.grade_submission(
  teacher_scope,
  submission.id,
  %{points: 95, feedback: "Excellent work!"}
)
```

## 🎯 Next Steps

### For End Users
1. Read the [USER_GUIDE.md](USER_GUIDE.md) for detailed instructions
2. Log in and start using the system
3. Explore all features
4. Provide feedback for improvements

### For Developers
1. Read [UI_IMPLEMENTATION_COMPLETE.md](UI_IMPLEMENTATION_COMPLETE.md)
2. Review the code in `lib/tasky_web/live/student/` and `lib/tasky_web/live/teacher/`
3. Check the test files for usage examples
4. Consider optional enhancements listed in docs

## 🔒 Authorization Summary

| Route | Student | Teacher | Admin |
|-------|---------|---------|-------|
| `/student/tasks/:id` | ✅ Own | ❌ | ❌ |
| `/student/my-tasks` | ✅ Own | ❌ | ❌ |
| `/tasks/:id/submissions` | ❌ | ✅ Own | ✅ All |
| `/tasks/:task_id/grade/:id` | ❌ | ✅ Own | ✅ All |

## 🎨 Status Colors

Understanding the visual indicators:

### Task Status
- 🔵 **Blue** - Published (active)
- ⚪ **Gray** - Draft (in progress)
- 🔴 **Red** - Archived (inactive)

### Submission Status
- ⚪ **Gray** - Not Started
- 🟡 **Yellow** - In Progress
- 🟢 **Green** - Completed

## 💡 Tips

### For Students
- Start tasks early
- Read task details carefully
- Use provided links
- Check back for grades
- Read teacher feedback

### For Teachers
- Create clear task names
- Provide helpful links
- Grade promptly
- Give constructive feedback
- Use statistics to track progress

## 🐛 Troubleshooting

**"I don't see any tasks"**
- Students: Ask teacher to create tasks
- Teachers: Create tasks at `/tasks`

**"Can't start a task"**
- Ensure you're logged in as a student
- Refresh the page
- Check that task is published

**"Can't grade submissions"**
- Student must mark task as complete first
- Ensure you created the task (or are admin)
- Check you're logged in as teacher/admin

**"Navigation doesn't work"**
- Clear browser cache
- Ensure JavaScript is enabled
- Check browser console for errors

## 📞 Getting Help

- **User Questions**: See [USER_GUIDE.md](USER_GUIDE.md)
- **Technical Issues**: See [SUBMISSION_UI_COMPLETE.md](SUBMISSION_UI_COMPLETE.md)
- **Backend API**: See [TASK_SUBMISSIONS_QUICKSTART.md](TASK_SUBMISSIONS_QUICKSTART.md)

## 🎉 Success!

You're all set! The task submission system is ready to use. Enjoy creating assignments, tracking student progress, and providing meaningful feedback.

**Happy teaching and learning!** 📚✨