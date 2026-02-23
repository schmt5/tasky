# Role-Based Authorization - Quick Start Guide

## 🚀 Quick Setup

Your Phoenix app now has three roles: **Admin**, **Teacher**, and **Student**.

## 📝 Default Configuration

- **Default role**: `student` (all new registrations)
- **Database field**: `users.role` (string, indexed)
- **Valid values**: `"admin"`, `"teacher"`, `"student"`

## 🎯 Common Use Cases

### 1. Protect a LiveView Route (Admin Only)

```elixir
# In router.ex
scope "/admin", TaskyWeb.Admin do
  pipe_through [:browser, :require_authenticated_user]

  live_session :admin,
    on_mount: [{TaskyWeb.UserAuth, :require_admin}] do
    live "/dashboard", DashboardLive, :index
    live "/users", UserLive, :index
  end
end
```

### 2. Protect a LiveView Route (Teacher or Admin)

```elixir
# In router.ex
scope "/assignments", TaskyWeb do
  pipe_through [:browser, :require_authenticated_user]

  live_session :teacher_or_admin,
    on_mount: [{TaskyWeb.UserAuth, :require_admin_or_teacher}] do
    live "/new", AssignmentLive.Form, :new
    live "/:id/edit", AssignmentLive.Form, :edit
  end
end
```

### 3. Show/Hide UI Elements Based on Role

```heex
<%!-- In any template/LiveView --%>
<%= if @current_scope && Tasky.Accounts.Scope.admin?(@current_scope) do %>
  <.link navigate={~p"/admin"}>Admin Panel</.link>
<% end %>

<%= if @current_scope && Tasky.Accounts.Scope.teacher?(@current_scope) do %>
  <.button navigate={~p"/assignments/new"}>Create Assignment</.button>
<% end %>

<%= if @current_scope && Tasky.Accounts.Scope.admin_or_teacher?(@current_scope) do %>
  <.link navigate={~p"/teacher/dashboard"}>Dashboard</.link>
<% end %>
```

### 4. Check Role in LiveView Logic

```elixir
defmodule TaskyWeb.AssignmentLive.Form do
  use TaskyWeb, :live_view
  alias Tasky.Accounts.Scope

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    # Only admins and teachers can delete
    if Scope.admin_or_teacher?(socket.assigns.current_scope) do
      # Delete logic here
      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end
end
```

### 5. Scope Data by Role in Context

```elixir
# In lib/tasky/assignments.ex
def list_assignments(%Scope{} = scope) do
  cond do
    Scope.admin?(scope) ->
      # Admins see all assignments
      Repo.all(Assignment)
    
    Scope.teacher?(scope) ->
      # Teachers see their own assignments
      Repo.all(from a in Assignment, where: a.teacher_id == ^scope.user.id)
    
    Scope.student?(scope) ->
      # Students see assignments they're enrolled in
      query = from a in Assignment,
        join: e in assoc(a, :enrollments),
        where: e.student_id == ^scope.user.id
      Repo.all(query)
    
    true ->
      []
  end
end
```

## 🛠️ Creating Users with Roles

### Via Seeds (Development)

```bash
# Run the seeds file
mix run priv/repo/seeds.exs
```

This creates:
- `admin@example.com` / `adminpassword123`
- `teacher@example.com` / `teacherpassword123`
- `student1@example.com` / `studentpassword123`
- `student2@example.com` / `studentpassword123`

### Via IEx Console

```elixir
# Start console
iex -S mix

# Create admin
{:ok, admin} = Tasky.Accounts.register_user(%{
  email: "admin@example.com",
  password: "securepassword123",
  role: "admin"
})

# Create teacher
{:ok, teacher} = Tasky.Accounts.register_user(%{
  email: "teacher@example.com",
  password: "securepassword123",
  role: "teacher"
})
```

### Change Existing User's Role

```elixir
# In IEx
user = Tasky.Accounts.get_user_by_email("user@example.com")
{:ok, updated} = Tasky.Accounts.update_user_role(user, %{role: "teacher"})
```

## 📋 Available Authorization Callbacks

Use in `live_session` blocks:

| Callback | Access Level |
|----------|--------------|
| `:require_authenticated` | Any logged-in user |
| `:require_admin` | Admin only |
| `:require_teacher` | Teacher only |
| `:require_student` | Student only |
| `:require_admin_or_teacher` | Admin or Teacher |

## 📋 Available Plugs

Use in controller scopes:

| Plug | Access Level |
|------|--------------|
| `:require_authenticated_user` | Any logged-in user |
| `:require_admin` | Admin only |
| `:require_teacher` | Teacher only |
| `:require_student` | Student only |
| `:require_admin_or_teacher` | Admin or Teacher |

## 🔍 Role Check Functions

### From `Tasky.Accounts.Scope`

```elixir
Scope.admin?(current_scope)           # Returns true if admin
Scope.teacher?(current_scope)         # Returns true if teacher
Scope.student?(current_scope)         # Returns true if student
Scope.admin_or_teacher?(current_scope) # Returns true if admin or teacher
Scope.role(current_scope)             # Returns role string
```

### From `TaskyWeb.RoleHelpers` (import in LiveView)

```elixir
import TaskyWeb.RoleHelpers

# Then use:
admin?(current_scope)
teacher?(current_scope)
student?(current_scope)
admin_or_teacher?(current_scope)
role(current_scope)
role_name("admin")  # Returns "Admin"
role_options()      # Returns [{"Admin", "admin"}, ...]
valid_roles()       # Returns ["admin", "teacher", "student"]
```

## 🎨 Example: Complete Feature with Roles

```elixir
# Router
scope "/assignments", TaskyWeb do
  pipe_through [:browser, :require_authenticated_user]

  # All authenticated users can view
  live_session :authenticated,
    on_mount: [{TaskyWeb.UserAuth, :require_authenticated}] do
    live "/", AssignmentLive.Index, :index
    live "/:id", AssignmentLive.Show, :show
  end

  # Only teachers and admins can create/edit
  live_session :teacher_admin,
    on_mount: [{TaskyWeb.UserAuth, :require_admin_or_teacher}] do
    live "/new", AssignmentLive.Form, :new
    live "/:id/edit", AssignmentLive.Form, :edit
  end
end

# LiveView
defmodule TaskyWeb.AssignmentLive.Index do
  use TaskyWeb, :live_view
  alias Tasky.Accounts.Scope

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Assignments
        <%= if Scope.admin_or_teacher?(@current_scope) do %>
          <:actions>
            <.link navigate={~p"/assignments/new"}>
              <.button>New Assignment</.button>
            </.link>
          </:actions>
        <% end %>
      </.header>

      <div :for={assignment <- @assignments}>
        <h3>{assignment.title}</h3>
        
        <%= if Scope.admin_or_teacher?(@current_scope) do %>
          <.link navigate={~p"/assignments/#{assignment}/edit"}>Edit</.link>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    assignments = Tasky.Assignments.list_assignments(socket.assigns.current_scope)
    {:ok, assign(socket, assignments: assignments)}
  end
end
```

## 🧪 Testing with Roles

```elixir
# In test helper
def user_fixture(attrs \\ %{}) do
  {:ok, user} =
    attrs
    |> Enum.into(%{
      email: unique_user_email(),
      password: valid_user_password(),
      role: "student"  # Default
    })
    |> Tasky.Accounts.register_user()

  user
end

# In test file
test "admin can access admin dashboard", %{conn: conn} do
  admin = user_fixture(%{role: "admin"})
  conn = log_in_user(conn, admin)
  
  {:ok, _view, html} = live(conn, ~p"/admin/dashboard")
  assert html =~ "Admin Dashboard"
end

test "student cannot access admin dashboard", %{conn: conn} do
  student = user_fixture(%{role: "student"})
  conn = log_in_user(conn, student)
  
  {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/dashboard")
end
```

## 🔥 Common Patterns

### Navigation Menu with Role-Based Links

```heex
<nav>
  <%= if @current_scope do %>
    <.link navigate={~p"/dashboard"}>Dashboard</.link>
    
    <%= if Scope.admin?(@current_scope) do %>
      <.link navigate={~p"/admin/users"}>Manage Users</.link>
    <% end %>
    
    <%= if Scope.admin_or_teacher?(@current_scope) do %>
      <.link navigate={~p"/assignments/new"}>Create Assignment</.link>
    <% end %>
    
    <%= if Scope.student?(@current_scope) do %>
      <.link navigate={~p"/student/assignments"}>My Assignments</.link>
    <% end %>
  <% end %>
</nav>
```

### Role Badge Component

```heex
<span class={[
  "inline-flex rounded-full px-2 py-1 text-xs font-semibold",
  @role == "admin" && "bg-purple-100 text-purple-800",
  @role == "teacher" && "bg-blue-100 text-blue-800",
  @role == "student" && "bg-green-100 text-green-800"
]}>
  {role_name(@role)}
</span>
```

## 📚 Need More Details?

See `ROLES.md` for the complete documentation including:
- Testing strategies
- Context-level authorization
- Admin user management UI
- Migration guides
- Troubleshooting

## 🎉 That's It!

Your role system is ready to use. Remember:
1. Always check roles on the **server side**
2. Use `live_session` for LiveViews
3. Use plugs for controllers
4. Pass `current_scope` to context functions
5. Test your authorization logic