# Role-Based Authorization System - Implementation Summary

## 🎉 What's Been Added

Your Phoenix application now has a **complete role-based authorization system** with three roles:

- **Admin** 👑 - Full system access
- **Teacher** 📚 - Can create and manage assignments
- **Student** 🎓 - Can view and complete assignments

## 📁 Files Created/Modified

### Database
- ✅ **Migration**: `priv/repo/migrations/*_add_role_to_users.exs`
  - Adds `role` field to `users` table
  - Default value: `"student"`
  - Indexed for performance

### Core Modules
- ✅ **User Schema**: `lib/tasky/accounts/user.ex`
  - Added `role` field
  - Added `registration_changeset/3` with role validation
  - Added `valid_roles/0` helper

- ✅ **Scope Module**: `lib/tasky/accounts/scope.ex`
  - Added `admin?/1`, `teacher?/1`, `student?/1`
  - Added `admin_or_teacher?/1`
  - Added `role/1` getter

- ✅ **Accounts Context**: `lib/tasky/accounts.ex`
  - Updated `register_user/1` to use new changeset
  - Added `change_user_role/2`
  - Added `update_user_role/2`
  - Added `list_users_by_role/1`
  - Added `list_all_users_grouped_by_role/0`

- ✅ **UserAuth**: `lib/tasky_web/user_auth.ex`
  - Added `on_mount :require_admin`
  - Added `on_mount :require_teacher`
  - Added `on_mount :require_student`
  - Added `on_mount :require_admin_or_teacher`
  - Added plug `require_admin/2`
  - Added plug `require_teacher/2`
  - Added plug `require_student/2`
  - Added plug `require_admin_or_teacher/2`

- ✅ **RoleHelpers**: `lib/tasky_web/role_helpers.ex`
  - Template-friendly role checking functions
  - Role display utilities

### Example Code
- ✅ **Admin UserLive**: `lib/tasky_web/live/admin/user_live.ex`
  - Complete user management interface
  - Role changing functionality

- ✅ **Seeds**: `priv/repo/seeds.exs`
  - Creates example users with all roles
  - Safely checks for existing users

### Documentation
- ✅ **ROLES.md** - Complete role system documentation
- ✅ **ROLES_QUICKSTART.md** - Quick reference guide
- ✅ **ROUTER_EXAMPLE.md** - Router configuration examples
- ✅ **NAVIGATION_EXAMPLE.md** - Navigation component examples
- ✅ **ROLE_SYSTEM_SUMMARY.md** - This file

## 🚀 Quick Start

### 1. Run the Migration

```bash
mix ecto.migrate
```

### 2. Create Test Users

```bash
mix run priv/repo/seeds.exs
```

This creates:
- `admin@example.com` / `adminpassword123`
- `teacher@example.com` / `teacherpassword123`
- `student1@example.com` / `studentpassword123`
- `student2@example.com` / `studentpassword123`

### 3. Add Routes to Your Router

```elixir
# In lib/tasky_web/router.ex

# Admin routes
scope "/admin", TaskyWeb.Admin, as: :admin do
  pipe_through [:browser, :require_authenticated_user, :require_admin]

  live_session :admin,
    on_mount: [{TaskyWeb.UserAuth, :require_admin}] do
    live "/", DashboardLive, :index
    live "/users", UserLive, :index
  end
end

# Teacher routes
scope "/teacher", TaskyWeb.Teacher, as: :teacher do
  pipe_through [:browser, :require_authenticated_user, :require_admin_or_teacher]

  live_session :teacher,
    on_mount: [{TaskyWeb.UserAuth, :require_admin_or_teacher}] do
    live "/", DashboardLive, :index
    live "/assignments", AssignmentLive, :index
  end
end

# Student routes
scope "/student", TaskyWeb.Student, as: :student do
  pipe_through [:browser, :require_authenticated_user, :require_student]

  live_session :student,
    on_mount: [{TaskyWeb.UserAuth, :require_student}] do
    live "/", DashboardLive, :index
    live "/assignments", AssignmentLive, :index
  end
end
```

See `ROUTER_EXAMPLE.md` for complete examples.

### 4. Update Your Navigation

Add role-based links to your layout or navigation component:

```heex
<%= if @current_scope && Tasky.Accounts.Scope.admin?(@current_scope) do %>
  <.link navigate={~p"/admin"}>Admin Panel</.link>
<% end %>

<%= if @current_scope && Tasky.Accounts.Scope.teacher?(@current_scope) do %>
  <.link navigate={~p"/teacher/dashboard"}>Teaching</.link>
<% end %>

<%= if @current_scope && Tasky.Accounts.Scope.student?(@current_scope) do %>
  <.link navigate={~p"/student/assignments"}>My Assignments</.link>
<% end %>
```

See `NAVIGATION_EXAMPLE.md` for complete examples.

## 🎯 Common Usage Patterns

### Protect a LiveView Route

```elixir
# Admin only
live_session :admin,
  on_mount: [{TaskyWeb.UserAuth, :require_admin}] do
  live "/admin/dashboard", Admin.DashboardLive, :index
end

# Teacher or Admin
live_session :teacher_admin,
  on_mount: [{TaskyWeb.UserAuth, :require_admin_or_teacher}] do
  live "/assignments/new", AssignmentLive.Form, :new
end
```

### Check Role in LiveView

```elixir
defmodule TaskyWeb.MyLive do
  use TaskyWeb, :live_view
  alias Tasky.Accounts.Scope

  def handle_event("delete", %{"id" => id}, socket) do
    if Scope.admin_or_teacher?(socket.assigns.current_scope) do
      # Delete logic
      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end
end
```

### Show/Hide UI Elements

```heex
<%= if Tasky.Accounts.Scope.admin?(@current_scope) do %>
  <.button phx-click="delete">Delete</.button>
<% end %>
```

### Scope Data by Role

```elixir
def list_assignments(%Scope{} = scope) do
  cond do
    Scope.admin?(scope) ->
      Repo.all(Assignment)
    
    Scope.teacher?(scope) ->
      Repo.all(from a in Assignment, where: a.teacher_id == ^scope.user.id)
    
    Scope.student?(scope) ->
      # Filter by enrollment
      Repo.all(from a in Assignment,
        join: e in assoc(a, :enrollments),
        where: e.student_id == ^scope.user.id)
    
    true ->
      []
  end
end
```

## 📋 Available Functions

### Authorization Callbacks (for LiveViews)

```elixir
on_mount: [{TaskyWeb.UserAuth, :require_authenticated}]
on_mount: [{TaskyWeb.UserAuth, :require_admin}]
on_mount: [{TaskyWeb.UserAuth, :require_teacher}]
on_mount: [{TaskyWeb.UserAuth, :require_student}]
on_mount: [{TaskyWeb.UserAuth, :require_admin_or_teacher}]
```

### Plugs (for Controllers)

```elixir
:require_authenticated_user
:require_admin
:require_teacher
:require_student
:require_admin_or_teacher
```

### Role Checking (Scope)

```elixir
Tasky.Accounts.Scope.admin?(current_scope)
Tasky.Accounts.Scope.teacher?(current_scope)
Tasky.Accounts.Scope.student?(current_scope)
Tasky.Accounts.Scope.admin_or_teacher?(current_scope)
Tasky.Accounts.Scope.role(current_scope)
```

### Role Helpers (import in LiveView)

```elixir
import TaskyWeb.RoleHelpers

admin?(current_scope)
teacher?(current_scope)
student?(current_scope)
admin_or_teacher?(current_scope)
role(current_scope)
role_name("admin")  # Returns "Admin"
role_options()      # For select inputs
valid_roles()       # ["admin", "teacher", "student"]
```

### Account Management

```elixir
# Change a user's role
Tasky.Accounts.update_user_role(user, %{role: "teacher"})

# List users by role
Tasky.Accounts.list_users_by_role("teacher")

# Get all users grouped by role
Tasky.Accounts.list_all_users_grouped_by_role()
```

## 🧪 Testing

```elixir
# Create test users with roles
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

# Test authorization
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

## 🔧 Managing Existing Users

### Via IEx Console

```elixir
# Start console
iex -S mix phx.server

# Update a user's role
user = Tasky.Accounts.get_user_by_email("user@example.com")
{:ok, updated_user} = Tasky.Accounts.update_user_role(user, %{role: "teacher"})

# Create a new admin
{:ok, admin} = Tasky.Accounts.register_user(%{
  email: "newadmin@example.com",
  password: "securepassword123",
  role: "admin"
})
```

### Via Admin UI

The example admin LiveView at `/admin/users` provides a UI for managing user roles.
See `lib/tasky_web/live/admin/user_live.ex` for the implementation.

## 📚 Documentation Files

- **ROLES.md** - Complete documentation with examples, testing, best practices
- **ROLES_QUICKSTART.md** - Quick reference for common tasks
- **ROUTER_EXAMPLE.md** - Router configuration examples
- **NAVIGATION_EXAMPLE.md** - Navigation UI examples
- **ROLE_SYSTEM_SUMMARY.md** - This file

## ✅ Next Steps

1. **Add routes** for your role-specific pages (see `ROUTER_EXAMPLE.md`)
2. **Update navigation** to show role-appropriate links (see `NAVIGATION_EXAMPLE.md`)
3. **Create LiveViews** for admin, teacher, and student dashboards
4. **Add authorization checks** in your existing LiveViews and contexts
5. **Write tests** for your authorization logic
6. **Create real admin accounts** (remove or change seed passwords)

## 🔐 Security Reminders

- ✅ Always check authorization on the **server side**
- ✅ Use `live_session` with `on_mount` for LiveViews
- ✅ Use plugs for controller routes
- ✅ Pass `current_scope` to all context functions
- ✅ Never trust client-side role checks
- ✅ Test all authorization scenarios
- ✅ Change default seed passwords in production

## 🐛 Troubleshooting

### User can't access protected route
1. Check the user's role: `Accounts.get_user!(id).role`
2. Verify the route uses correct plug/on_mount
3. Ensure `current_scope` is assigned

### Role not updating
1. Check changeset: `Accounts.change_user_role(user, %{role: "teacher"})`
2. Verify role value is valid: `"admin"`, `"teacher"`, or `"student"`
3. Use `update_user_role/2`, not just `change_user_role/2`

### Authorization always fails
1. Verify `fetch_current_scope_for_user` is in browser pipeline
2. Check that user is logged in: `@current_scope.user` should not be nil
3. Inspect current_scope in LiveView mount

## 🎓 Learn More

- Read `ROLES.md` for comprehensive documentation
- See `ROLES_QUICKSTART.md` for common patterns
- Check `ROUTER_EXAMPLE.md` for routing examples
- Review Phoenix LiveView docs on authorization
- Follow the project guidelines in `AGENTS.md`

## 💡 Tips

- Start with the quickstart examples
- Build admin features first
- Test with seed users before production
- Keep authorization logic in contexts
- Use helper functions for cleaner templates
- Document role requirements for each feature

---

**Your role-based authorization system is ready to use!** 🚀

For questions or issues, refer to the documentation files or the Phoenix/Ecto docs.