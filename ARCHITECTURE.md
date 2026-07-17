# Task Submission System - Architecture Overview

## 🏗️ System Architecture

### High-Level Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Browser (Client)                        │
│                                                                 │
│  ┌──────────────────┐              ┌──────────────────┐        │
│  │  Student View    │              │  Teacher View    │        │
│  │                  │              │                  │        │
│  │  • My Tasks      │              │  • Tasks List    │        │
│  │  • Task Detail   │              │  • Submissions   │        │
│  │  • View Grades   │              │  • Grading Form  │        │
│  └──────────────────┘              └──────────────────┘        │
│           │                                  │                  │
└───────────┼──────────────────────────────────┼─────────────────┘
            │                                  │
            │          LiveView WebSocket      │
            │                                  │
┌───────────┴──────────────────────────────────┴─────────────────┐
│                    Phoenix LiveView Layer                       │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐   │
│  │               Router (Authorization)                   │   │
│  │                                                        │   │
│  │  ┌──────────────────┐      ┌──────────────────┐      │   │
│  │  │ :student scope   │      │ :tasks scope     │      │   │
│  │  │ (Student only)   │      │ (Teacher/Admin)  │      │   │
│  │  └──────────────────┘      └──────────────────┘      │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐   │
│  │                   LiveView Modules                     │   │
│  │                                                        │   │
│  │  Student.*           Teacher.*         TaskLive.*     │   │
│  │  ├─ TaskLive         ├─ SubmissionsLive  ├─ Index   │   │
│  │  └─ MyTasksLive      └─ GradeLive        ├─ Show    │   │
│  │                                           └─ Form    │   │
│  └────────────────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────────────────┘
                          │
┌─────────────────────────┴───────────────────────────────────────┐
│                     Context Layer (Business Logic)              │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐   │
│  │                  Tasky.Tasks Context                   │   │
│  │                                                        │   │
│  │  • list_my_submissions(scope)                         │   │
│  │  • get_or_create_submission(scope, task_id)           │   │
│  │  • update_submission_status(scope, id, status)        │   │
│  │  • complete_task(scope, submission_id)                │   │
│  │  • list_task_submissions(scope, task_id)              │   │
│  │  • grade_submission(scope, id, attrs)                 │   │
│  │  • get_submission!(scope, id)                         │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐   │
│  │              Tasky.Accounts.Scope                      │   │
│  │                                                        │   │
│  │  • for_user(user)                                     │   │
│  │  • student?(scope)                                    │   │
│  │  • admin_or_teacher?(scope)                           │   │
│  └────────────────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────────────────┘
                          │
┌─────────────────────────┴───────────────────────────────────────┐
│                    Data Layer (Ecto/Database)                   │
│                                                                 │
│  ┌─────────────┐   ┌──────────────┐   ┌──────────────┐       │
│  │    tasks    │   │ task_        │   │    users     │       │
│  │             │   │ submissions  │   │              │       │
│  │ • id        │───│ • id         │───│ • id         │       │
│  │ • name      │   │ • task_id    │   │ • email      │       │
│  │ • content   │   │ • student_id │───│ • role       │       │
│  │ • status    │   │ • status     │   │ • ...        │       │
│  │ • position  │   │ • completed_at│   └──────────────┘       │
│  │ • user_id   │   │ • points     │         ▲                 │
│  └─────────────┘   │ • feedback   │         │                 │
│                    │ • graded_at  │─────────┘                 │
│                    │ • graded_by_id│ (teacher)                │
│                    └──────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
```

## 🔄 Data Flow

### Student Workflow

```
1. Student Views Task
   Browser → Router → Student.TaskLive
                    ↓
              Tasks.get_task!(scope, id)
                    ↓
              Tasks.get_or_create_submission(scope, task_id)
                    ↓
              Database Query
                    ↓
              Render with task & submission data

2. Student Starts Task
   Browser (Click) → handle_event("start_task")
                           ↓
                    Tasks.update_submission_status(scope, id, "in_progress")
                           ↓
                    Database Update
                           ↓
                    Updated submission assigned to socket
                           ↓
                    Browser (Re-render with new status)

3. Student Completes Task
   Browser (Click) → handle_event("complete_task")
                           ↓
                    Tasks.complete_task(scope, id)
                           ↓
                    Database Update (status + completed_at)
                           ↓
                    Updated submission assigned to socket
                           ↓
                    Browser (Show "waiting for grade")

4. Student Views Grade
   Teacher grades → Database Update
                           ↓
   Student refreshes → Tasks.get_submission!(scope, id)
                           ↓
                    Database Query (with grade)
                           ↓
                    Browser (Display points + feedback)
```

### Teacher Workflow

```
1. Teacher Views Submissions
   Browser → Router → Teacher.SubmissionsLive
                    ↓
              Tasks.list_task_submissions(scope, task_id)
                    ↓
              Database Query (with preloads: student, graded_by)
                    ↓
              Calculate stats (total, completed, graded, pending)
                    ↓
              Render with submissions & stats

2. Teacher Grades Submission
   Browser (Click Grade) → Navigate to Teacher.GradeLive
                                    ↓
                           Tasks.get_submission!(scope, id)
                                    ↓
                           Database Query (with preloads)
                                    ↓
                           Render grading form

   Browser (Submit Form) → handle_event("save_grade")
                                    ↓
                           Tasks.grade_submission(scope, id, attrs)
                                    ↓
                           Database Update:
                             • points
                             • feedback
                             • graded_at (automatic)
                             • graded_by_id (automatic)
                                    ↓
                           Navigate back to submissions list
                                    ↓
                           Stats updated
```

## 🔐 Authorization Flow

```
Request → Router Pipeline → Plug Chain → LiveView on_mount → Context Function
                            │
                            ├─ :browser
                            ├─ :require_authenticated_user
                            ├─ :require_student (for student routes)
                            └─ :require_admin_or_teacher (for teacher routes)
                                          │
                                          ▼
                            on_mount callback checks:
                              • User authenticated?
                              • User has correct role?
                              • Redirect if not authorized
                                          │
                                          ▼
                            Context function checks:
                              • Scope has correct role?
                              • User owns the resource?
                              • Return data or raise error
```

### Authorization Matrix

| Route | Pipeline | on_mount | Context Check |
|-------|----------|----------|---------------|
| `/student/tasks/:id` | `:require_authenticated_user` + `:require_student` | `require_student` | Student owns submission |
| `/student/my-tasks` | `:require_authenticated_user` + `:require_student` | `require_student` | Student's submissions only |
| `/tasks/:id/submissions` | `:require_authenticated_user` + `:require_admin_or_teacher` | `require_admin_or_teacher` | Teacher owns task |
| `/tasks/:task_id/grade/:id` | `:require_authenticated_user` + `:require_admin_or_teacher` | `require_admin_or_teacher` | Teacher owns task |

## 📊 Database Schema

### Relationships

```
users (1) ──────────────┬─────────────── (many) tasks
                        │                        │
                        │                        │
                        │                        │ (one task has many submissions)
                        │                        │
                        └────────┬───────────────┘
                                 │
                                 │ (one student has many submissions)
                                 │
                                 ▼
                        task_submissions
                                 │
                                 │ (graded_by references users)
                                 │
                                 └──────────────> users (grader)
```

### Submission State Machine

```
┌─────────────┐
│ not_started │ ◄─── Initial state (auto-created)
└──────┬──────┘
       │ Student clicks "Start Task"
       │ Tasks.update_submission_status(scope, id, "in_progress")
       ▼
┌─────────────┐
│ in_progress │
└──────┬──────┘
       │ Student clicks "Mark as Complete"
       │ Tasks.complete_task(scope, id)
       │ Sets: completed_at = DateTime.utc_now()
       ▼
┌─────────────┐
│  completed  │
└──────┬──────┘
       │ Teacher grades
       │ Tasks.grade_submission(scope, id, attrs)
       │ Sets: points, feedback, graded_at, graded_by_id
       ▼
┌─────────────┐
│   graded    │ (still status = "completed", but has grade data)
└─────────────┘
```

## 🎨 UI Component Hierarchy

### Student Views

```
Student.TaskLive
├── Layouts.app
│   ├── Header (with navigation)
│   └── Main content
│       ├── Task content section
│       │   ├── Task name
│       │   ├── Tiptap editor (teacher content locked,
│       │   │   answer fields editable, autosaved)
│       │   └── Dateien tab (attachments + upload slots)
│       └── Action section
│           ├── "Abschliessen" button (flush-check + required uploads)
│           └── Review states (completed / approved / sent back)
│               ├── Feedback
│               └── Reviewed date

Student.MyTasksLive
├── Layouts.app
│   └── Main content
│       ├── Statistics cards
│       │   ├── Total tasks
│       │   ├── Completed
│       │   └── Graded
│       └── Submissions table
│           └── For each submission:
│               ├── Task name
│               ├── Status badge
│               ├── Completed date
│               ├── Grade (if graded)
│               └── View button
```

### Teacher Views

```
Teacher.SubmissionsLive
├── Layouts.app
│   └── Main content
│       ├── Statistics cards
│       │   ├── Total students
│       │   ├── Completed
│       │   ├── Graded
│       │   └── Pending
│       └── Submissions table
│           └── For each submission:
│               ├── Student avatar & email
│               ├── Status badge
│               ├── Completed date
│               ├── Grade (if graded)
│               ├── Graded by (if graded)
│               └── Action button (Grade/Edit Grade)

Teacher.GradeLive
├── Layouts.app
│   └── Main content
│       ├── Submission details section
│       │   ├── Student info
│       │   ├── Task info
│       │   ├── Completion date
│       │   └── Current grade (if updating)
│       └── Grading form
│           ├── Points input (0-100)
│           ├── Feedback textarea
│           ├── Cancel button
│           └── Save button
```

## 🔧 Key Technical Patterns

### 1. Authorization Pattern
```elixir
# Every context function takes a scope as first argument
def list_my_submissions(%Scope{user: user} = _scope) when user.role == "student"

# Scope enforces authorization at data access level
def get_submission!(%Scope{user: user} = scope, submission_id) do
  submission = Repo.get!(TaskSubmission, submission_id) |> Repo.preload(...)
  
  cond do
    user.role == "student" and submission.student_id == user.id -> submission
    Scope.admin_or_teacher?(scope) -> submission
    true -> raise Ecto.NoResultsError
  end
end
```

### 2. LiveView Mount Pattern
```elixir
def mount(%{"id" => id}, _session, socket) do
  # Get data using scope from socket.assigns.current_scope
  task = Tasks.get_task!(socket.assigns.current_scope, id)
  
  # Auto-create submission (student view)
  {:ok, submission} = Tasks.get_or_create_submission(
    socket.assigns.current_scope,
    id
  )
  
  # Assign to socket
  {:ok, assign(socket, task: task, submission: submission)}
end
```

### 3. Event Handler Pattern
```elixir
def handle_event("complete_task", %{"id" => id}, socket) do
  # Call context function with scope
  {:ok, submission} = Tasks.complete_task(
    socket.assigns.current_scope,
    id
  )
  
  # Update socket state and provide feedback
  {:noreply,
   socket
   |> put_flash(:info, "Task completed!")
   |> assign(:submission, submission)}
end
```

### 4. Statistics Pattern
```elixir
# Calculate stats from list of submissions
stats = %{
  total: length(submissions),
  completed: Enum.count(submissions, &(&1.status == "completed")),
  graded: Enum.count(submissions, &(&1.graded_at != nil)),
  pending: Enum.count(submissions, &(&1.status == "completed" and is_nil(&1.graded_at)))
}
```

## 🧪 Testing Architecture

```
Test Layer
├── LiveView Tests
│   ├── Student Tests
│   │   ├── Integration tests (full workflow)
│   │   ├── Navigation tests
│   │   └── Authorization tests
│   └── Teacher Tests
│       ├── Integration tests (grading workflow)
│       ├── Stats accuracy tests
│       └── Authorization tests
│
└── Context Tests (already existed)
    ├── CRUD operations
    ├── Authorization
    └── Business logic
```

## 📦 Deployment Architecture

```
Production Environment
├── Application Server (Phoenix)
│   ├── LiveView processes (stateful)
│   ├── Database connection pool
│   └── PubSub (for real-time updates)
│
├── Database (SQLite/Postgres)
│   ├── users table
│   ├── tasks table
│   └── task_submissions table
│
└── Static Assets
    ├── Compiled CSS (Tailwind)
    ├── Compiled JS (esbuild)
    └── Images (Heroicons)
```

## 🚀 Performance Considerations

### Database Queries
- **Preloading**: All associations preloaded to avoid N+1 queries
- **Indexing**: Foreign keys indexed (task_id, student_id, graded_by_id)
- **Selective loading**: Only load needed fields

### LiveView Optimization
- **Stateful connections**: Maintains state across interactions
- **Minimal re-renders**: Only updates changed assigns
- **Efficient diffing**: Phoenix tracks changes automatically

### Caching Strategy
- **No caching needed**: Data updates are infrequent
- **LiveView state**: Keeps current page data in memory
- **Database**: Fast enough for current scale

## 🔄 Future Scalability

### Horizontal Scaling
- Multiple Phoenix nodes with PubSub
- Shared database
- Session storage in distributed cache

### Feature Extensions
- File storage service (S3/local)
- Background job processing (Oban)
- Email service integration
- Analytics database (separate read replica)

---

This architecture provides a solid foundation for a scalable, maintainable task submission system with clear separation of concerns and proper authorization at every layer.