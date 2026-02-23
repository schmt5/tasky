# Task Submissions System Documentation

## Overview

The task submissions system tracks which students have completed which tasks, including grading and feedback from teachers.

## 📊 Database Schema

### `task_submissions` Table

| Field | Type | Description |
|-------|------|-------------|
| `id` | bigint | Primary key |
| `task_id` | bigint | Reference to tasks table (required) |
| `student_id` | bigint | Reference to users table (required) |
| `status` | string | Current status (default: "not_started") |
| `completed_at` | utc_datetime | When student completed the task |
| `points` | integer | Points awarded by teacher |
| `feedback` | string | Teacher feedback |
| `graded_at` | utc_datetime | When teacher graded |
| `graded_by_id` | bigint | Reference to teacher who graded |
| `inserted_at` | utc_datetime | Record creation timestamp |
| `updated_at` | utc_datetime | Record update timestamp |

### Status Values

- **`"not_started"`** - Default state, student hasn't begun
- **`"in_progress"`** - Student is actively working on the task
- **`"completed"`** - Student has marked the task as complete

### Indexes

- Unique index on `[:task_id, :student_id]` - One submission per student per task
- Index on `[:student_id]` - Fast lookup of student's submissions
- Index on `[:task_id]` - Fast lookup of task's submissions
- Index on `[:status]` - Filter by status
- Index on `[:graded_by_id]` - Find submissions graded by teacher

### Foreign Key Constraints

- `task_id` → `tasks.id` (on_delete: :delete_all)
- `student_id` → `users.id` (on_delete: :delete_all)
- `graded_by_id` → `users.id` (on_delete: :nilify_all)

## 🔧 Schema Module

**Location:** `lib/tasky/tasks/task_submission.ex`

### Associations

```elixir
belongs_to :task, Tasky.Tasks.Task
belongs_to :student, Tasky.Accounts.User
belongs_to :graded_by, Tasky.Accounts.User
```

### Related Associations

**Task schema:**
```elixir
has_many :submissions, Tasky.Tasks.TaskSubmission
```

**User schema:**
```elixir
has_many :task_submissions, Tasky.Tasks.TaskSubmission, foreign_key: :student_id
has_many :graded_submissions, Tasky.Tasks.TaskSubmission, foreign_key: :graded_by_id
```

## 📝 Context Functions

All functions are in the `Tasky.Tasks` context.

### For Students

#### `get_or_create_submission(scope, task_id)`

Gets existing submission or creates a new one with "not_started" status.

```elixir
# When a student views a task
{:ok, submission} = Tasks.get_or_create_submission(socket.assigns.current_scope, task_id)
```

**Returns:**
- `{:ok, %TaskSubmission{}}` - Existing or new submission
- `{:error, changeset}` - If creation fails

**Authorization:** Students only

#### `list_my_submissions(scope)`

Lists all submissions for the current student.

```elixir
submissions = Tasks.list_my_submissions(socket.assigns.current_scope)
```

**Returns:** List of submissions with preloaded tasks

**Authorization:** Students only

#### `update_submission_status(scope, submission_id, status)`

Updates the status of a submission.

```elixir
{:ok, submission} = Tasks.update_submission_status(
  socket.assigns.current_scope,
  submission_id,
  "in_progress"
)
```

**Valid statuses:** `"not_started"`, `"in_progress"`, `"completed"`

**Returns:**
- `{:ok, %TaskSubmission{}}` - Updated submission
- `{:error, :unauthorized}` - If student doesn't own submission
- `{:error, changeset}` - If validation fails

**Authorization:** Students can only update their own submissions

#### `complete_task(scope, submission_id)`

Marks a task as completed. Sets status to "completed" and sets `completed_at` timestamp.

```elixir
{:ok, submission} = Tasks.complete_task(socket.assigns.current_scope, submission_id)
```

**Returns:**
- `{:ok, %TaskSubmission{}}` - Completed submission
- `{:error, :unauthorized}` - If student doesn't own submission

**Authorization:** Students can only complete their own submissions

### For Teachers/Admins

#### `list_task_submissions(scope, task_id)`

Lists all submissions for a specific task.

```elixir
submissions = Tasks.list_task_submissions(socket.assigns.current_scope, task_id)
```

**Returns:** List of submissions with preloaded student and grader info

**Authorization:** Teachers and admins only

#### `grade_submission(scope, submission_id, attrs)`

Grades a submission with points and feedback.

```elixir
{:ok, submission} = Tasks.grade_submission(
  socket.assigns.current_scope,
  submission_id,
  %{points: 85, feedback: "Great work! Could improve X"}
)
```

**Attributes:**
- `points` (integer, >= 0) - Points awarded
- `feedback` (string, optional) - Teacher feedback

**Automatically sets:**
- `graded_at` - Current timestamp
- `graded_by_id` - Current teacher's ID

**Returns:**
- `{:ok, %TaskSubmission{}}` - Graded submission
- `{:error, :unauthorized}` - If not teacher/admin
- `{:error, changeset}` - If validation fails

**Authorization:** Teachers and admins only

### For Both

#### `get_submission!(scope, submission_id)`

Gets a single submission with authorization checks.

```elixir
submission = Tasks.get_submission!(socket.assigns.current_scope, submission_id)
```

**Returns:** Submission with preloaded associations

**Authorization:**
- Students can only view their own submissions
- Teachers/admins can view any submission
- Raises `Ecto.NoResultsError` if unauthorized

#### `change_submission(submission, attrs \\ %{})`

Returns a changeset for tracking submission changes.

```elixir
changeset = Tasks.change_submission(submission, %{status: "in_progress"})
```

## 🎯 Usage Examples

### Student Workflow

#### 1. View Task and Get Submission

```elixir
def mount(%{"id" => task_id}, _session, socket) do
  task = Tasks.get_task!(socket.assigns.current_scope, task_id)
  {:ok, submission} = Tasks.get_or_create_submission(socket.assigns.current_scope, task_id)
  
  {:ok,
   socket
   |> assign(:task, task)
   |> assign(:submission, submission)}
end
```

#### 2. Start Working on Task

```elixir
def handle_event("start_task", %{"id" => id}, socket) do
  {:ok, submission} = Tasks.update_submission_status(
    socket.assigns.current_scope,
    id,
    "in_progress"
  )
  
  {:noreply, assign(socket, :submission, submission)}
end
```

#### 3. Mark as Complete

```elixir
def handle_event("complete_task", %{"id" => id}, socket) do
  {:ok, submission} = Tasks.complete_task(socket.assigns.current_scope, id)
  
  {:noreply,
   socket
   |> put_flash(:info, "Task completed!")
   |> assign(:submission, submission)}
end
```

### Teacher Workflow

#### 1. View All Submissions for a Task

```elixir
def mount(%{"task_id" => task_id}, _session, socket) do
  task = Tasks.get_task!(socket.assigns.current_scope, task_id)
  submissions = Tasks.list_task_submissions(socket.assigns.current_scope, task_id)
  
  {:ok,
   socket
   |> assign(:task, task)
   |> assign(:submissions, submissions)}
end
```

#### 2. Grade a Submission

```elixir
def handle_event("grade", %{"id" => id, "points" => points, "feedback" => feedback}, socket) do
  case Tasks.grade_submission(
    socket.assigns.current_scope,
    id,
    %{points: String.to_integer(points), feedback: feedback}
  ) do
    {:ok, submission} ->
      submissions = Tasks.list_task_submissions(socket.assigns.current_scope, socket.assigns.task.id)
      
      {:noreply,
       socket
       |> put_flash(:info, "Submission graded successfully")
       |> assign(:submissions, submissions)}
    
    {:error, changeset} ->
      {:noreply, put_flash(socket, :error, "Failed to grade submission")}
  end
end
```

## 🎨 Template Examples

### Student View - Task Detail

```heex
<div>
  <h1>{@task.name}</h1>
  
  <div class="mt-4">
    <span class={[
      "badge",
      @submission.status == "not_started" && "badge-secondary",
      @submission.status == "in_progress" && "badge-warning",
      @submission.status == "completed" && "badge-success"
    ]}>
      {String.replace(@submission.status, "_", " ") |> String.capitalize()}
    </span>
  </div>
  
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
  
  <%= if @submission.status == "completed" do %>
    <div class="alert alert-success">
      <span>✓ Completed on {Calendar.strftime(@submission.completed_at, "%B %d, %Y")}</span>
    </div>
    
    <%= if @submission.graded_at do %>
      <div class="mt-4">
        <h3>Grade</h3>
        <p><strong>Points:</strong> {@submission.points}</p>
        <%= if @submission.feedback do %>
          <p><strong>Feedback:</strong> {@submission.feedback}</p>
        <% end %>
        <p class="text-sm text-gray-500">
          Graded by {@submission.graded_by.email} on {Calendar.strftime(@submission.graded_at, "%B %d, %Y")}
        </p>
      </div>
    <% else %>
      <p class="text-sm text-gray-500">Waiting for teacher to grade...</p>
    <% end %>
  <% end %>
</div>
```

### Teacher View - Submissions List

```heex
<div>
  <h1>Submissions for {@task.name}</h1>
  
  <table class="table">
    <thead>
      <tr>
        <th>Student</th>
        <th>Status</th>
        <th>Completed At</th>
        <th>Points</th>
        <th>Actions</th>
      </tr>
    </thead>
    <tbody>
      <tr :for={submission <- @submissions}>
        <td>{submission.student.email}</td>
        <td>
          <span class={[
            "badge",
            submission.status == "not_started" && "badge-secondary",
            submission.status == "in_progress" && "badge-warning",
            submission.status == "completed" && "badge-success"
          ]}>
            {String.replace(submission.status, "_", " ") |> String.capitalize()}
          </span>
        </td>
        <td>
          <%= if submission.completed_at do %>
            {Calendar.strftime(submission.completed_at, "%B %d, %Y")}
          <% else %>
            —
          <% end %>
        </td>
        <td>
          <%= if submission.graded_at do %>
            {submission.points}
          <% else %>
            <span class="text-gray-400">Not graded</span>
          <% end %>
        </td>
        <td>
          <%= if submission.status == "completed" do %>
            <.link navigate={~p"/tasks/#{@task.id}/submissions/#{submission.id}/grade"}>
              <.button size="sm">Grade</.button>
            </.link>
          <% end %>
        </td>
      </tr>
    </tbody>
  </table>
</div>
```

### Teacher View - Grading Form

```heex
<div>
  <h1>Grade Submission</h1>
  
  <div class="mb-4">
    <p><strong>Student:</strong> {@submission.student.email}</p>
    <p><strong>Task:</strong> {@submission.task.name}</p>
    <p><strong>Completed:</strong> {Calendar.strftime(@submission.completed_at, "%B %d, %Y at %I:%M %p")}</p>
  </div>
  
  <.form for={@form} id="grading-form" phx-submit="grade">
    <.input field={@form[:points]} type="number" label="Points" min="0" required />
    <.input field={@form[:feedback]} type="textarea" label="Feedback (optional)" />
    
    <.button type="submit">Save Grade</.button>
  </.form>
</div>
```

## 🔒 Authorization Rules

### Students

✅ **Can:**
- View their own submissions
- Create submissions (automatically via `get_or_create_submission`)
- Update their own submission status
- Complete their own tasks

❌ **Cannot:**
- View other students' submissions
- Grade submissions
- Modify points or feedback
- Delete submissions

### Teachers

✅ **Can:**
- View all submissions for any task
- Grade any submission
- Provide feedback
- View submission statistics

❌ **Cannot:**
- Modify student's status
- Complete tasks on behalf of students
- View submissions for tasks they didn't create (unless admin)

### Admins

✅ **Can:**
- Everything teachers can do
- View all submissions system-wide
- Override grades if needed

## 🧪 Testing Examples

### Test Student Submission Creation

```elixir
test "student can create submission for a task", %{conn: conn} do
  student = user_fixture(%{role: "student"})
  teacher = user_fixture(%{role: "teacher"})
  task = task_fixture(teacher)
  
  conn = log_in_user(conn, student)
  
  {:ok, view, _html} = live(conn, ~p"/tasks/#{task.id}")
  
  # Submission should be auto-created
  assert has_element?(view, "[data-status='not_started']")
end
```

### Test Task Completion

```elixir
test "student can complete a task", %{conn: conn} do
  student = user_fixture(%{role: "student"})
  teacher = user_fixture(%{role: "teacher"})
  task = task_fixture(teacher)
  
  conn = log_in_user(conn, student)
  {:ok, view, _html} = live(conn, ~p"/tasks/#{task.id}")
  
  # Start task
  view |> element("button", "Start Task") |> render_click()
  assert has_element?(view, "[data-status='in_progress']")
  
  # Complete task
  view |> element("button", "Mark as Complete") |> render_click()
  assert has_element?(view, "[data-status='completed']")
end
```

### Test Teacher Grading

```elixir
test "teacher can grade a completed submission", %{conn: conn} do
  student = user_fixture(%{role: "student"})
  teacher = user_fixture(%{role: "teacher"})
  task = task_fixture(teacher)
  
  # Student completes task
  {:ok, submission} = Tasks.get_or_create_submission(Scope.for_user(student), task.id)
  {:ok, _} = Tasks.complete_task(Scope.for_user(student), submission.id)
  
  # Teacher grades
  conn = log_in_user(conn, teacher)
  {:ok, view, _html} = live(conn, ~p"/tasks/#{task.id}/submissions/#{submission.id}/grade")
  
  view
  |> form("#grading-form", %{points: 85, feedback: "Great work!"})
  |> render_submit()
  
  assert_redirected(view, ~p"/tasks/#{task.id}/submissions")
  
  # Check submission was graded
  updated = Repo.get!(TaskSubmission, submission.id)
  assert updated.points == 85
  assert updated.feedback == "Great work!"
  assert updated.graded_by_id == teacher.id
end
```

## 📊 Statistics and Reporting

### Get Completion Statistics

```elixir
def get_task_statistics(scope, task_id) do
  if Scope.admin_or_teacher?(scope) do
    submissions = list_task_submissions(scope, task_id)
    
    %{
      total_students: length(submissions),
      not_started: Enum.count(submissions, &(&1.status == "not_started")),
      in_progress: Enum.count(submissions, &(&1.status == "in_progress")),
      completed: Enum.count(submissions, &(&1.status == "completed")),
      graded: Enum.count(submissions, &(&1.graded_at != nil)),
      average_points: calculate_average_points(submissions)
    }
  end
end

defp calculate_average_points(submissions) do
  graded = Enum.filter(submissions, &(&1.points != nil))
  
  if length(graded) > 0 do
    Enum.sum(Enum.map(graded, & &1.points)) / length(graded)
  else
    0
  end
end
```

## 🚀 Next Steps

1. **Add Routes** - Create student and teacher submission routes
2. **Build UI** - Create LiveViews for students and teachers
3. **Add Statistics** - Display completion rates and averages
4. **Notifications** - Notify students when graded
5. **Export** - Export grades to CSV
6. **File Uploads** - Add file attachment support (future)

## 📝 Summary

The task submissions system provides:

- ✅ Simple task completion tracking (3 statuses)
- ✅ Teacher grading with points and feedback
- ✅ One submission per student per task
- ✅ Role-based authorization
- ✅ Timestamps for completion and grading
- ✅ Track who graded each submission
- ✅ Extensible design for future features

For questions or to extend functionality, refer to this documentation and the source code in `lib/tasky/tasks.ex` and `lib/tasky/tasks/task_submission.ex`.