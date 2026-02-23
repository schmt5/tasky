# Role-Based Authorization Cheat Sheet

Quick reference for implementing role-based authorization in your Phoenix app.

## 🎯 Three Roles Available

| Role | Description | Use Case |
|------|-------------|----------|
| `admin` | Full system access | System administrators |
| `teacher` | Create/manage content | Teachers, instructors |
| `student` | View/consume content | Students, learners |

## 📝 Quick Commands

### Create Users with Roles

```elixir
# In IEx console (iex -S mix phx.server)
alias Tasky.Accounts

# Create admin
{:ok, admin} = Accounts.register_user(%{
  email: "admin@example.com",
  password: "password123456",
  role: "admin"
})

# Create teacher
{:ok, teacher} = Accounts.register_user(%{
  email: "teacher@example.com",
  password: "password123456",
  role: "teacher"
})

# Create student (default role)
{:ok, student} = Accounts.register_user(%{
  email: "student@example.com",
  password: "password123456"
  # role: "student" is default
})
```

### Change User Role

```elixir
# Get user
user = Accounts.get_user_by_email("user@example.com")

# Update role
{:ok, updated} = Accounts.update_user_role(user, %{role: "teacher"})
```

### List Users by Role

```elixir
# Get all admins
admins = Accounts.list_users_by_role("admin")

# Get all teachers
teachers = Accounts.list_users_by_role("teacher")

# Get all students
students = Accounts.list_users_by_role("student")

# Get all users grouped
users = Accounts.list_all_users_grouped_by_role()
```

## 🛣️ Router Configuration

### Admin Routes (Admin Only)

```elixir
scope "/admin", TaskyWeb.Admin, as: :admin do
  pipe_through [:browser, :require_authenticated_user, :require_admin]

  live_session :admin,
    on_mount: [{TaskyWeb.UserAuth, :require_admin}] do
    live "/", DashboardLive, :index
    live "/users", UserLive, :index
  end
end
```

### Teacher Routes (Teacher or Admin)

```elixir
scope "/teacher", TaskyWeb.Teacher, as: :teacher do
  pipe_through [:browser, :require_authenticated_user, :require_admin_or_teacher]

  live_session :teacher,
    on_mount: [{TaskyWeb.UserAuth, :require_admin_or_teacher}] do
    live "/", DashboardLive, :index
    live "/assignments", AssignmentLive, :index
  end
end
```

### Student Routes (Student Only)

```elixir
scope "/student", TaskyWeb.Student, as: :student do
  pipe_through [:browser, :require_authenticated_user, :require_student]

  live_session :student,
    on_mount: [{TaskyWeb.UserAuth, :require_student}] do
    live "/", DashboardLive, :index
  end
end
```

### Shared Routes (All Authenticated)

```elixir
scope "/", TaskyWeb do
  pipe_through [:browser, :require_authenticated_user]

  live_session :authenticated,
    on_mount: [{TaskyWeb.UserAuth, :require_authenticated}] do
    live "/dashboard", DashboardLive, :index
  end
end
```

## 🎨 Template Usage

### Check Roles in Templates

```heex
<%!-- Admin only --%>
<%= if @current_scope && Tasky.Accounts.Scope.admin?(@current_scope) do %>
  <.link navigate={~p"/admin"}>Admin Panel</.link>
<% end %>

<%!-- Teacher only --%>
<%= if @current_scope && Tasky.Accounts.Scope.teacher?(@current_scope) do %>
  <.button>Create Assignment</.button>
<% end %>

<%!-- Student only --%>
<%= if @current_scope && Tasky.Accounts.Scope.student?(@current_scope) do %>
  <.link navigate={~p"/student/assignments"}>My Assignments</.link>
<% end %>

<%!-- Admin or Teacher --%>
<%= if @current_scope && Tasky.Accounts.Scope.admin_or_teacher?(@current_scope) do %>
  <.button>Manage Content</.button>
<% end %>

<%!-- Any authenticated user --%>
<%= if @current_scope && @current_scope.user do %>
  <.link navigate={~p"/profile"}>Profile</.link>
<% end %>
```

### Using RoleHelpers (Shorter Syntax)

```elixir
# In your LiveView module
import TaskyWeb.RoleHelpers
```

```heex
<%!-- Then in template --%>
<%= if admin?(@current_scope) do %>
  <.link navigate={~p"/admin"}>Admin</.link>
<% end %>

<%= if teacher?(@current_scope) do %>
  <.link navigate={~p"/teacher"}>Teaching</.link>
<% end %>

<%= if student?(@current_scope) do %>
  <.link navigate={~p"/student"}>Student</.link>
<% end %>

<%= if admin_or_teacher?(@current_scope) do %>
  <.button>Manage</.button>
<% end %>

<%!-- Display role --%>
<span>Role: {role_name(role(@current_scope))}</span>
```

## 💻 LiveView Usage

### Check Role in Event Handlers

```elixir
defmodule TaskyWeb.MyLive do
  use TaskyWeb, :live_view
  alias Tasky.Accounts.Scope

  def handle_event("delete", %{"id" => id}, socket) do
    if Scope.admin_or_teacher?(socket.assigns.current_scope) do
      # Perform action
      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end
end
```

### Check Role in Mount

```elixir
def mount(_params, _session, socket) do
  if socket.assigns.current_scope && 
     Scope.admin?(socket.assigns.current_scope) do
    {:ok, socket}
  else
    {:ok, 
     socket
     |> put_flash(:error, "Admin access required")
     |> redirect(to: ~p"/")}
  end
end
```

## 🗄️ Context Functions

### Scope Data by Role

```elixir
defmodule Tasky.Assignments do
  alias Tasky.Accounts.Scope

  def list_assignments(%Scope{} = scope) do
    cond do
      Scope.admin?(scope) ->
        # Admins see everything
        Repo.all(Assignment)
      
      Scope.teacher?(scope) ->
        # Teachers see their own
        Repo.all(from a in Assignment, 
          where: a.teacher_id == ^scope.user.id)
      
      Scope.student?(scope) ->
        # Students see enrolled assignments
        Repo.all(from a in Assignment,
          join: e in assoc(a, :enrollments),
          where: e.student_id == ^scope.user.id)
      
      true ->
        []
    end
  end

  def create_assignment(%Scope{} = scope, attrs) do
    if Scope.admin_or_teacher?(scope) do
      %Assignment{}
      |> Assignment.changeset(attrs)
      |> Ecto.Changeset.put_change(:teacher_id, scope.user.id)
      |> Repo.insert()
    else
      {:error, :unauthorized}
    end
  end
end
```

### Always Pass Scope

```elixir
# ✅ DO THIS
Assignments.list_assignments(socket.assigns.current_scope)

# ❌ NOT THIS
Assignments.list_assignments()
```

## 🧪 Testing

### Create Test Users

```elixir
def user_fixture(attrs \\ %{}) do
  {:ok, user} =
    attrs
    |> Enum.into(%{
      email: unique_user_email(),
      password: valid_user_password(),
      role: "student"
    })
    |> Tasky.Accounts.register_user()

  user
end
```

### Test Authorization

```elixir
test "admin can access admin page", %{conn: conn} do
  admin = user_fixture(%{role: "admin"})
  conn = log_in_user(conn, admin)
  
  {:ok, _view, html} = live(conn, ~p"/admin")
  assert html =~ "Admin"
end

test "student cannot access admin page", %{conn: conn} do
  student = user_fixture(%{role: "student"})
  conn = log_in_user(conn, student)
  
  {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin")
end
```

## 📋 Available Functions Reference

### Authorization Callbacks (LiveView)

```elixir
on_mount: [{TaskyWeb.UserAuth, :require_authenticated}]
on_mount: [{TaskyWeb.UserAuth, :require_admin}]
on_mount: [{TaskyWeb.UserAuth, :require_teacher}]
on_mount: [{TaskyWeb.UserAuth, :require_student}]
on_mount: [{TaskyWeb.UserAuth, :require_admin_or_teacher}]
```

### Plugs (Controller)

```elixir
:require_authenticated_user
:require_admin
:require_teacher
:require_student
:require_admin_or_teacher
```

### Scope Functions

```elixir
alias Tasky.Accounts.Scope

Scope.admin?(current_scope)           # true if admin
Scope.teacher?(current_scope)         # true if teacher
Scope.student?(current_scope)         # true if student
Scope.admin_or_teacher?(current_scope) # true if admin or teacher
Scope.role(current_scope)             # returns role string
```

### RoleHelpers (import first)

```elixir
import TaskyWeb.RoleHelpers

admin?(current_scope)
teacher?(current_scope)
student?(current_scope)
admin_or_teacher?(current_scope)
role(current_scope)
role_name("admin")     # "Admin"
role_options()         # [{"Admin", "admin"}, ...]
valid_roles()          # ["admin", "teacher", "student"]
```

### Account Functions

```elixir
alias Tasky.Accounts

Accounts.update_user_role(user, %{role: "teacher"})
Accounts.list_users_by_role("admin")
Accounts.list_all_users_grouped_by_role()
Accounts.change_user_role(user, %{role: "admin"})
```

## 🎨 UI Components

### Role Badge

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

### Role Select Input

```heex
<.input
  field={@form[:role]}
  type="select"
  label="Role"
  options={[
    {"Admin", "admin"},
    {"Teacher", "teacher"},
    {"Student", "student"}
  ]}
/>
```

## 🚨 Common Mistakes

### ❌ Wrong: Checking role in template only

```heex
<%!-- Client side only - NOT SECURE --%>
<%= if admin?(@current_scope) do %>
  <.button phx-click="delete">Delete</.button>
<% end %>
```

### ✅ Right: Also check in event handler

```elixir
def handle_event("delete", _, socket) do
  if Scope.admin?(socket.assigns.current_scope) do
    # Delete logic
    {:noreply, socket}
  else
    {:noreply, put_flash(socket, :error, "Unauthorized")}
  end
end
```

### ❌ Wrong: Not passing scope to context

```elixir
def list_assignments do
  Repo.all(Assignment)
end
```

### ✅ Right: Always pass scope

```elixir
def list_assignments(%Scope{} = scope) do
  # Filter by scope.user.id and role
end
```

### ❌ Wrong: Duplicate live_session names

```elixir
live_session :admin, ... do
  live "/admin", AdminLive
end

live_session :admin, ... do  # ❌ Same name
  live "/settings", SettingsLive
end
```

### ✅ Right: Unique live_session names

```elixir
live_session :admin, ... do
  live "/admin", AdminLive
end

live_session :admin_settings, ... do
  live "/admin/settings", SettingsLive
end
```

## 🔧 Quick Setup Checklist

- [ ] Run migration: `mix ecto.migrate`
- [ ] Run seeds: `mix run priv/repo/seeds.exs`
- [ ] Add routes to router.ex
- [ ] Update navigation with role checks
- [ ] Test with different roles
- [ ] Add authorization to context functions
- [ ] Write tests for authorization
- [ ] Change seed passwords for production

## 📚 Documentation Files

- **ROLES.md** - Complete documentation
- **ROLES_QUICKSTART.md** - Quick start guide
- **ROLES_CHEATSHEET.md** - This file
- **ROUTER_EXAMPLE.md** - Router examples
- **NAVIGATION_EXAMPLE.md** - Navigation examples
- **ADMIN_SETUP_EXAMPLE.md** - Admin setup guide
- **ROLE_SYSTEM_SUMMARY.md** - Implementation summary

## 💡 Pro Tips

1. **Always check on server** - Never trust client-side checks
2. **Use live_session** - For LiveView route protection
3. **Use plugs** - For controller route protection
4. **Pass scope everywhere** - To context functions
5. **Test all roles** - Write tests for each role scenario
6. **Keep it DRY** - Use helper functions
7. **Log role changes** - For audit trails
8. **Document permissions** - Make it clear who can do what

## 🆘 Troubleshooting

| Problem | Solution |
|---------|----------|
| Can't access protected route | Check user role in database |
| Always redirected | Verify on_mount callback matches plug |
| Role not updating | Use `update_user_role/2`, not `change_user_role/2` |
| current_scope is nil | Ensure `fetch_current_scope_for_user` in pipeline |
| Authorization fails | Check both on_mount and plug are set |

---

**Keep this cheat sheet handy while building your app!** 🚀