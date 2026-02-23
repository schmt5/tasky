# Role-Based Authorization System

This document describes the role-based authorization system implemented in this Phoenix application.

## Overview

The application supports three user roles:
- **Admin**: Full system access, can manage all users and content
- **Teacher**: Can create and manage assignments, view student work
- **Student**: Can view and complete assignments

## Database Schema

The `users` table includes a `role` field:
- Type: `string`
- Default: `"student"`
- Valid values: `"admin"`, `"teacher"`, `"student"`
- Indexed for performance

## User Registration

### Default Registration (Student Role)

By default, new users are registered as students. The registration process automatically assigns the `"student"` role.

### Registration with Role Selection (Optional)

If you want to allow users to select their role during registration, update the `UserLive.Registration` module:

```elixir
# In lib/tasky_web/live/user_live/registration.ex

# Update the form to include role selection:
<.input
  field={@form[:role]}
  type="select"
  label="Role"
  options={TaskyWeb.RoleHelpers.role_options()}
  value="student"
/>
```

### Admin-Only Registration

For production environments, you typically want only admins to create teacher/admin accounts. See the "Admin User Management" section below.

## Authorization in LiveViews

### Using `on_mount` Callbacks

Phoenix LiveView provides `on_mount` callbacks for authorization. The following callbacks are available:

#### Require Any Authenticated User
```elixir
live_session :require_authenticated_user,
  on_mount: [{TaskyWeb.UserAuth, :require_authenticated}] do
  live "/profile", ProfileLive, :index
end
```

#### Require Admin Role
```elixir
live_session :require_admin,
  on_mount: [{TaskyWeb.UserAuth, :require_admin}] do
  live "/admin/users", Admin.UserLive, :index
end
```

#### Require Teacher Role
```elixir
live_session :require_teacher,
  on_mount: [{TaskyWeb.UserAuth, :require_teacher}] do
  live "/teacher/dashboard", Teacher.DashboardLive, :index
end
```

#### Require Admin or Teacher Role
```elixir
live_session :require_admin_or_teacher,
  on_mount: [{TaskyWeb.UserAuth, :require_admin_or_teacher}] do
  live "/assignments/new", AssignmentLive.Form, :new
end
```

#### Require Student Role
```elixir
live_session :require_student,
  on_mount: [{TaskyWeb.UserAuth, :require_student}] do
  live "/student/assignments", Student.AssignmentLive, :index
end
```

### Example Router Configuration

```elixir
# In lib/tasky_web/router.ex

scope "/admin", TaskyWeb.Admin do
  pipe_through [:browser, :require_authenticated_user, :require_admin]

  live_session :admin,
    on_mount: [{TaskyWeb.UserAuth, :require_admin}] do
    live "/dashboard", DashboardLive, :index
    live "/users", UserLive, :index
  end
end

scope "/teacher", TaskyWeb.Teacher do
  pipe_through [:browser, :require_authenticated_user, :require_admin_or_teacher]

  live_session :teacher,
    on_mount: [{TaskyWeb.UserAuth, :require_admin_or_teacher}] do
    live "/dashboard", DashboardLive, :index
    live "/assignments", AssignmentLive, :index
  end
end

scope "/student", TaskyWeb.Student do
  pipe_through [:browser, :require_authenticated_user, :require_student]

  live_session :student,
    on_mount: [{TaskyWeb.UserAuth, :require_student}] do
    live "/dashboard", DashboardLive, :index
  end
end
```

## Authorization in Controllers

Use plugs for controller-based routes:

```elixir
scope "/admin", TaskyWeb.Admin do
  pipe_through [:browser, :require_authenticated_user, :require_admin]

  get "/reports", ReportController, :index
  post "/reports/generate", ReportController, :generate
end
```

Available plugs:
- `:require_authenticated_user` - Any logged-in user
- `:require_admin` - Admin users only
- `:require_teacher` - Teacher users only
- `:require_student` - Student users only
- `:require_admin_or_teacher` - Admin or teacher users

## Checking Roles in Templates

### Using the Scope Module

The `@current_scope` assign is available in all LiveViews and templates:

```heex
<%= if @current_scope && Tasky.Accounts.Scope.admin?(@current_scope) do %>
  <.link navigate={~p"/admin/dashboard"}>Admin Dashboard</.link>
<% end %>

<%= if @current_scope && Tasky.Accounts.Scope.teacher?(@current_scope) do %>
  <.link navigate={~p"/teacher/dashboard"}>Teacher Dashboard</.link>
<% end %>

<%= if @current_scope && Tasky.Accounts.Scope.student?(@current_scope) do %>
  <.link navigate={~p"/student/dashboard"}>Student Dashboard</.link>
<% end %>

<%= if @current_scope && Tasky.Accounts.Scope.admin_or_teacher?(@current_scope) do %>
  <.button>Create Assignment</.button>
<% end %>
```

### Using RoleHelpers

Import `TaskyWeb.RoleHelpers` for cleaner syntax:

```elixir
# In your LiveView module
import TaskyWeb.RoleHelpers
```

Then in templates:

```heex
<%= if admin?(@current_scope) do %>
  <.link navigate={~p"/admin"}>Admin Panel</.link>
<% end %>

<%= if teacher?(@current_scope) do %>
  <.link navigate={~p"/teacher"}>Teacher Dashboard</.link>
<% end %>

<%= if student?(@current_scope) do %>
  <.link navigate={~p"/student"}>My Assignments</.link>
<% end %>

<%= if admin_or_teacher?(@current_scope) do %>
  <.button>Create New Assignment</.button>
<% end %>

<div>Your role: {role_name(role(@current_scope))}</div>
```

## Role Management Functions

The `Tasky.Accounts` context provides functions for role management:

### Change User Role

```elixir
# Get a changeset for changing a user's role
changeset = Accounts.change_user_role(user, %{role: "teacher"})

# Update a user's role
{:ok, updated_user} = Accounts.update_user_role(user, %{role: "teacher"})
```

### List Users by Role

```elixir
# Get all teachers
teachers = Accounts.list_users_by_role("teacher")

# Get all students
students = Accounts.list_users_by_role("student")

# Get all admins
admins = Accounts.list_users_by_role("admin")
```

### List All Users Grouped by Role

```elixir
users_by_role = Accounts.list_all_users_grouped_by_role()
# Returns: %{"admin" => [...], "teacher" => [...], "student" => [...]}
```

## Admin User Management

### Creating an Admin User

You can create an admin user via IEx console or seeds:

#### Using IEx Console

```elixir
# Start IEx
mix phx.server
# or
iex -S mix

# Create an admin user
{:ok, admin} = Tasky.Accounts.register_user(%{
  email: "admin@example.com",
  password: "securepassword123",
  role: "admin"
})
```

#### Using Seeds File

```elixir
# In priv/repo/seeds.exs

alias Tasky.Accounts

# Create admin user
{:ok, _admin} = Accounts.register_user(%{
  email: "admin@example.com",
  password: "securepassword123",
  role: "admin"
})

# Create teacher user
{:ok, _teacher} = Accounts.register_user(%{
  email: "teacher@example.com",
  password: "securepassword123",
  role: "teacher"
})

# Create student user
{:ok, _student} = Accounts.register_user(%{
  email: "student@example.com",
  password: "securepassword123",
  role: "student"
})
```

Then run: `mix run priv/repo/seeds.exs`

### Admin User Management UI

Create a LiveView for admins to manage user roles:

```elixir
# lib/tasky_web/live/admin/user_live.ex
defmodule TaskyWeb.Admin.UserLive do
  use TaskyWeb, :live_view
  
  alias Tasky.Accounts

  @impl true
  def mount(_params, _session, socket) do
    users = Accounts.list_all_users_grouped_by_role()
    {:ok, assign(socket, users: users)}
  end

  @impl true
  def handle_event("change_role", %{"user_id" => user_id, "role" => role}, socket) do
    user = Accounts.get_user!(user_id)
    
    case Accounts.update_user_role(user, %{role: role}) do
      {:ok, _updated_user} ->
        users = Accounts.list_all_users_grouped_by_role()
        {:noreply, 
         socket
         |> put_flash(:info, "User role updated successfully")
         |> assign(users: users)}
      
      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update user role")}
    end
  end
end
```

## Authorization Logic in LiveViews

### Manual Authorization Checks

You can perform manual authorization checks in LiveView callbacks:

```elixir
defmodule TaskyWeb.AssignmentLive.Form do
  use TaskyWeb, :live_view
  
  alias Tasky.Accounts.Scope

  @impl true
  def mount(_params, _session, socket) do
    # Check if user has permission to create assignments
    if socket.assigns.current_scope && 
       Scope.admin_or_teacher?(socket.assigns.current_scope) do
      {:ok, assign(socket, :form, to_form(%{}))}
    else
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to access this page")
       |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("save", %{"assignment" => params}, socket) do
    # Verify authorization before saving
    if Scope.admin_or_teacher?(socket.assigns.current_scope) do
      # Save logic here
      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end
end
```

## Context-Level Authorization

Always pass the `current_scope` to context functions for proper scoping:

```elixir
# In lib/tasky/assignments.ex
defmodule Tasky.Assignments do
  import Ecto.Query
  alias Tasky.Repo
  alias Tasky.Accounts.Scope

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
        Repo.all(from a in Assignment,
          join: e in assoc(a, :enrollments),
          where: e.student_id == ^scope.user.id)
      
      true ->
        []
    end
  end

  def create_assignment(%Scope{} = scope, attrs) do
    # Only teachers and admins can create assignments
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

## Best Practices

1. **Always use `live_session` with `on_mount` callbacks** for LiveView authorization
2. **Always use plugs** for controller route authorization
3. **Pass `current_scope` to context functions** for proper data scoping
4. **Never trust client-side authorization** - always verify on the server
5. **Use the most specific authorization** - prefer role-specific checks over general ones
6. **Test authorization** - write tests for each authorization scenario
7. **Log authorization failures** - help debug permission issues
8. **Consistent error messages** - provide clear feedback to users

## Testing Authorization

### Testing LiveView Authorization

```elixir
# test/tasky_web/live/admin/user_live_test.exs
defmodule TaskyWeb.Admin.UserLiveTest do
  use TaskyWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "as admin" do
    setup do
      admin = user_fixture(%{role: "admin"})
      %{conn: log_in_user(build_conn(), admin), admin: admin}
    end

    test "can access admin dashboard", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/dashboard")
      assert html =~ "Admin Dashboard"
    end
  end

  describe "as student" do
    setup do
      student = user_fixture(%{role: "student"})
      %{conn: log_in_user(build_conn(), student), student: student}
    end

    test "cannot access admin dashboard", %{conn: conn} do
      {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/dashboard")
    end
  end
end
```

### Testing Context-Level Authorization

```elixir
# test/tasky/assignments_test.exs
defmodule Tasky.AssignmentsTest do
  use Tasky.DataCase

  alias Tasky.Assignments
  alias Tasky.Accounts.Scope

  test "teachers can create assignments" do
    teacher = user_fixture(%{role: "teacher"})
    scope = Scope.for_user(teacher)
    
    assert {:ok, assignment} = Assignments.create_assignment(scope, %{title: "Test"})
    assert assignment.teacher_id == teacher.id
  end

  test "students cannot create assignments" do
    student = user_fixture(%{role: "student"})
    scope = Scope.for_user(student)
    
    assert {:error, :unauthorized} = Assignments.create_assignment(scope, %{title: "Test"})
  end
end
```

## Migration Guide for Existing Users

If you already have users in your database, run this migration to set their roles:

```elixir
# Create a new migration: mix ecto.gen.migration set_default_roles

defmodule Tasky.Repo.Migrations.SetDefaultRoles do
  use Ecto.Migration

  def up do
    # Set all existing users to "student" role
    execute "UPDATE users SET role = 'student' WHERE role IS NULL"
    
    # Or set specific users as admins by email
    execute """
    UPDATE users 
    SET role = 'admin' 
    WHERE email IN ('admin@example.com', 'another.admin@example.com')
    """
  end

  def down do
    # No need to revert
  end
end
```

## Troubleshooting

### "You must be an admin to access this page" Error

1. Check that the user is logged in: `@current_scope.user` should not be nil
2. Verify the user's role in the database: `Accounts.get_user!(id)`
3. Ensure the route is using the correct `on_mount` callback or plug

### Role Not Updating

1. Check that the changeset is valid: `Accounts.change_user_role(user, %{role: "teacher"})`
2. Verify the role is one of the valid values: `"admin"`, `"teacher"`, `"student"`
3. Make sure you're calling `update_user_role/2`, not just `change_user_role/2`

### Authorization Check Always Fails

1. Ensure `current_scope` is properly assigned in your LiveView/Controller
2. Check that the `fetch_current_scope_for_user` plug is in the browser pipeline
3. Verify the user's role field is set in the database

## Summary

The role-based authorization system provides:
- ✅ Three predefined roles: admin, teacher, student
- ✅ LiveView `on_mount` callbacks for route authorization
- ✅ Controller plugs for route authorization
- ✅ Helper functions for template role checks
- ✅ Context functions for data scoping
- ✅ Easy-to-extend role management

For questions or issues, refer to the Phoenix LiveView and Ecto documentation, or consult the `AGENTS.md` file for project-specific guidelines.