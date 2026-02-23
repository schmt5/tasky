# Task Submissions - Quick Start Guide

## 🚀 What Was Built

A complete system for tracking student task completion and teacher grading.

**Key Features:**
- ✅ Students can start, work on, and complete tasks
- ✅ Teachers can grade completed tasks with points and feedback
- ✅ Simple 3-status workflow: not_started → in_progress → completed
- ✅ One submission per student per task
- ✅ Full authorization (students see only their own)

## 📊 Database

**Table:** `task_submissions`

**Key Fields:**
- `task_id` - Which task
- `student_id` - Which student
- `status` - "not_started", "in_progress", or "completed"
- `completed_at` - When completed
- `points` - Teacher-assigned points (integer)
- `feedback` - Teacher feedback (string)
- `graded_at` - When graded
- `graded_by_id` - Which teacher graded

**Migration:** Already run ✓

## 🎯 Quick Usage

### For Students

#### Get or Create Submission
```elixir
{:ok, submission} = Tasks.get_or_create_submission(
  socket.assigns.current_scope,
  task_id
)
```

#### Start Task
```elixir
{:ok, submission} = Tasks.update_submission_status(
  socket.assigns.current_scope,
  submission_id,
  "in_progress"
)
```

#### Complete Task
```elixir
{:ok, submission} = Tasks.complete_task(
  socket.assigns.current_scope,
  submission_id
)
```

#### List My Submissions
```elixir
submissions = Tasks.list_my_submissions(socket.assigns.current_scope)
```

### For Teachers

#### View All Submissions for a Task
```elixir
submissions = Tasks.list_task_submissions(
  socket.assigns.current_scope,
  task_id
)
```

#### Grade a Submission
```elixir
{:ok, submission} = Tasks.grade_submission(
  socket.assigns.current_scope,
  submission_id,
  %{points: 85, feedback: "Great work!"}
)
```

#### Get Specific Submission
```elixir
submission = Tasks.get_submission!(
  socket.assigns.current_scope,
  submission_id
)
```

## 🎨 Template Examples

### Student View - Task Status Badge

```heex
<span class={[
  "badge",
  @submission.status == "not_started" && "badge-secondary",
  @submission.status == "in_progress" && "badge-warning",
  @submission.status == "completed" && "badge-success"
]}>
  {String.replace(@submission.status, "_", " ") |> String.capitalize()}
</span>
```

### Student View - Action Buttons

```heex
<%= if @submission.status == "not_started" do %>
  <.button phx-click="start_task" phx-value-id={@submission.id}>
    Start Task
  </.button>
<% end %>

<%= if @submission.status == "in_progress" do %>
  <.button phx-click="complete_task" phx-value-id={@submission.id}>
    Mark as Complete
  </.button>
<% end %>

<%= if @submission.status == "completed" && @submission.graded_at do %>
  <div class="alert alert-success">
    <p><strong>Points:</strong> {@submission.points}</p>
    <p><strong>Feedback:</strong> {@submission.feedback}</p>
  </div>
<% end %>
```

### Teacher View - Submissions Table

```heex
<table class="table">
  <thead>
    <tr>
      <th>Student</th>
      <th>Status</th>
      <th>Points</th>
      <th>Actions</th>
    </tr>
  </thead>
  <tbody>
    <tr :for={submission <- @submissions}>
      <td>{submission.student.email}</td>
      <td>
        <span class="badge">{submission.status}</span>
      </td>
      <td>
        <%= if submission.points do %>
          {submission.points}
        <% else %>
          <span class="text-gray-400">Not graded</span>
        <% end %>
      </td>
      <td>
        <%= if submission.status == "completed" && !submission.graded_at do %>
          <.link navigate={~p"/tasks/#{@task.id}/grade/#{submission.id}"}>
            Grade
          </.link>
        <% end %>
      </td>
    </tr>
  </tbody>
</table>
```

### Teacher View - Grading Form

```heex
<.form for={@form} id="grade-form" phx-submit="save_grade">
  <.input 
    field={@form[:points]} 
    type="number" 
    label="Points" 
    min="0" 
    required 
  />
  
  <.input 
    field={@form[:feedback]} 
    type="textarea" 
    label="Feedback (optional)" 
    rows="4"
  />
  
  <.button type="submit">Save Grade</.button>
</.form>
```

## 📝 LiveView Example - Student Task Page

```elixir
defmodule TaskyWeb.Student.TaskLive do
  use TaskyWeb, :live_view
  alias Tasky.Tasks

  def mount(%{"id" => task_id}, _session, socket) do
    task = Tasks.get_task!(socket.assigns.current_scope, task_id)
    {:ok, submission} = Tasks.get_or_create_submission(
      socket.assigns.current_scope, 
      task_id
    )

    {:ok,
     socket
     |> assign(:task, task)
     |> assign(:submission, submission)}
  end

  def handle_event("start_task", %{"id" => id}, socket) do
    {:ok, submission} = Tasks.update_submission_status(
      socket.assigns.current_scope,
      id,
      "in_progress"
    )

    {:noreply, assign(socket, :submission, submission)}
  end

  def handle_event("complete_task", %{"id" => id}, socket) do
    {:ok, submission} = Tasks.complete_task(
      socket.assigns.current_scope,
      id
    )

    {:noreply,
     socket
     |> put_flash(:info, "Task completed!")
     |> assign(:submission, submission)}
  end
end
```

## 📝 LiveView Example - Teacher Grading Page

```elixir
defmodule TaskyWeb.Teacher.GradeLive do
  use TaskyWeb, :live_view
  alias Tasky.Tasks

  def mount(%{"task_id" => task_id, "submission_id" => sub_id}, _session, socket) do
    submission = Tasks.get_submission!(socket.assigns.current_scope, sub_id)
    form = to_form(%{"points" => nil, "feedback" => ""})

    {:ok,
     socket
     |> assign(:submission, submission)
     |> assign(:form, form)}
  end

  def handle_event("save_grade", %{"points" => points, "feedback" => feedback}, socket) do
    case Tasks.grade_submission(
      socket.assigns.current_scope,
      socket.assigns.submission.id,
      %{points: String.to_integer(points), feedback: feedback}
    ) do
      {:ok, _submission} ->
        {:noreply,
         socket
         |> put_flash(:info, "Submission graded successfully")
         |> push_navigate(to: ~p"/tasks/#{socket.assigns.submission.task_id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to grade submission")}
    end
  end
end
```

## 🔒 Authorization Summary

| Action | Student | Teacher | Admin |
|--------|---------|---------|-------|
| View own submissions | ✅ | ✅ | ✅ |
| View all submissions | ❌ | ✅ | ✅ |
| Create submission | ✅ (auto) | ❌ | ❌ |
| Update status | ✅ (own) | ❌ | ❌ |
| Complete task | ✅ (own) | ❌ | ❌ |
| Grade submission | ❌ | ✅ | ✅ |

## 🎯 Typical Workflows

### Student Completes a Task

1. Student visits `/tasks/:id`
2. System auto-creates submission with status "not_started"
3. Student clicks "Start Task" → status becomes "in_progress"
4. Student clicks "Mark Complete" → status becomes "completed", `completed_at` set
5. Student sees "Waiting for teacher to grade..."
6. Teacher grades
7. Student sees points and feedback

### Teacher Grades Submissions

1. Teacher visits `/tasks/:id/submissions`
2. Sees list of all student submissions
3. Clicks "Grade" on a completed submission
4. Enters points (e.g., 85) and feedback (e.g., "Great work!")
5. Clicks "Save Grade"
6. `graded_at`, `graded_by_id` automatically set
7. Student can now see their grade

## 🧪 Testing in IEx

```elixir
# Start console
iex -S mix phx.server

# Create test data
alias Tasky.{Accounts, Tasks}
alias Tasky.Accounts.Scope

# Get or create users
{:ok, student} = Accounts.register_user(%{
  email: "student@test.com",
  password: "password123456",
  role: "student"
})

{:ok, teacher} = Accounts.register_user(%{
  email: "teacher@test.com",
  password: "password123456",
  role: "teacher"
})

# Create a task (assuming you have a task_fixture or similar)
# task = create_task_somehow()

# Student gets or creates submission
{:ok, submission} = Tasks.get_or_create_submission(
  Scope.for_user(student),
  task.id
)

# Student completes task
{:ok, submission} = Tasks.complete_task(
  Scope.for_user(student),
  submission.id
)

# Teacher grades
{:ok, submission} = Tasks.grade_submission(
  Scope.for_user(teacher),
  submission.id,
  %{points: 90, feedback: "Excellent!"}
)

# Check result
submission.points # => 90
submission.feedback # => "Excellent!"
submission.graded_by_id # => teacher.id
```

## 🚀 Next Steps

1. **Add Routes** - Create student submission routes
   ```elixir
   # In router.ex, in student scope
   live "/tasks/:id", Student.TaskLive, :show
   live "/my-submissions", Student.SubmissionsLive, :index
   ```

2. **Add Teacher Routes** - Create grading routes
   ```elixir
   # In router.ex, in teacher scope
   live "/tasks/:task_id/submissions", Teacher.SubmissionsLive, :index
   live "/tasks/:task_id/grade/:id", Teacher.GradeLive, :edit
   ```

3. **Build UI** - Create LiveViews using the examples above

4. **Add Statistics** - Show completion rates on teacher dashboard
   ```elixir
   completed = Enum.count(submissions, &(&1.status == "completed"))
   total = length(submissions)
   percentage = completed / total * 100
   ```

5. **Add Notifications** - Notify students when graded (optional)

## 📚 Full Documentation

See `TASK_SUBMISSIONS.md` for:
- Complete API reference
- All context functions
- Advanced examples
- Testing strategies
- Statistics and reporting

## ✅ Summary

You now have:
- ✅ Database table created and migrated
- ✅ Schema module with associations
- ✅ Context functions for all operations
- ✅ Role-based authorization
- ✅ Simple 3-status workflow
- ✅ Teacher grading with points and feedback
- ✅ Ready to build UI

**Everything is implemented and ready to use!** 🎉