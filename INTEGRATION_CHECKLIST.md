# Role-Based Authorization - Integration Checklist

Follow this checklist to integrate the role-based authorization system into your application.

## ✅ Phase 1: Database & Core Setup (COMPLETED)

These steps have already been completed:

- [x] Migration created and run (`*_add_role_to_users.exs`)
- [x] User schema updated with `role` field
- [x] Scope module extended with role helpers
- [x] Accounts context updated with role functions
- [x] UserAuth module updated with authorization callbacks
- [x] RoleHelpers module created
- [x] Seed data created with example users
- [x] Admin UserLive example created

## 🚀 Phase 2: Router Integration (YOUR NEXT STEP)

### Step 1: Add Admin Routes

Open `lib/tasky_web/router.ex` and add the admin scope before the dev routes:

```elixir
## Admin routes - Add this section

scope "/admin", TaskyWeb.Admin, as: :admin do
  pipe_through [:browser, :require_authenticated_user, :require_admin]

  live_session :admin,
    on_mount: [{TaskyWeb.UserAuth, :require_admin}] do
    live "/users", UserLive, :index
  end
end
```

**Test it:**
1. Run `mix phx.server`
2. Log in as admin (`admin@example.com` / `adminpassword123`)
3. Visit `http://localhost:4000/admin/users`
4. You should see the user management interface ✓

### Step 2: Add Navigation Links (Optional)

Update `lib/tasky_web/components/layouts.ex` to add an admin link:

```elixir
# In the app/1 function, add this to your navigation:
<%= if @current_scope && Tasky.Accounts.Scope.admin?(@current_scope) do %>
  <.link navigate={~p"/admin/users"} class="btn btn-ghost">
    Manage Users
  </.link>
<% end %>
```

### Step 3: Add Teacher Routes (When Ready)

```elixir
scope "/teacher", TaskyWeb.Teacher, as: :teacher do
  pipe_through [:browser, :require_authenticated_user, :require_admin_or_teacher]

  live_session :teacher,
    on_mount: [{TaskyWeb.UserAuth, :require_admin_or_teacher}] do
    live "/dashboard", DashboardLive, :index
  end
end
```

### Step 4: Add Student Routes (When Ready)

```elixir
scope "/student", TaskyWeb.Student, as: :student do
  pipe_through [:browser, :require_authenticated_user, :require_student]

  live_session :student,
    on_mount: [{TaskyWeb.UserAuth, :require_student}] do
    live "/dashboard", DashboardLive, :index
  end
end
```

## 📝 Phase 3: Create Your LiveViews

### For Teacher Dashboard

```bash
mkdir -p lib/tasky_web/live/teacher
```

Create `lib/tasky_web/live/teacher/dashboard_live.ex`:

```elixir
defmodule TaskyWeb.Teacher.DashboardLive do
  use TaskyWeb, :live_view

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Teacher Dashboard
        <:subtitle>Welcome, {<@current_scope.user.email}</:subtitle>
      </.header>

      <div class="mt-8">
        <p>Teacher-specific content goes here</p>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Teacher Dashboard")}
  end
end
```

### For Student Dashboard

```bash
mkdir -p lib/tasky_web/live/student
```

Create `lib/tasky_web/live/student/dashboard_live.ex`:

```elixir
defmodule TaskyWeb.Student.DashboardLive do
  use TaskyWeb, :live_view

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Student Dashboard
        <:subtitle>Welcome, {<@current_scope.user.email}</:subtitle>
      </.header>

      <div class="mt-8">
        <p>Student-specific content goes here</p>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Student Dashboard")}
  end
end
```

## 🔐 Phase 4: Add Authorization to Existing Features

### In Your Context Modules

Update your context functions to accept and use `current_scope`:

```elixir
# Example: lib/tasky/assignments.ex
defmodule Tasky.Assignments do
  alias Tasky.Accounts.Scope

  def list_assignments(%Scope{} = scope) do
    cond do
      Scope.admin?(scope) ->
        Repo.all(Assignment)
      
      Scope.teacher?(scope) ->
        Repo.all(from a in Assignment, where: a.teacher_id == ^scope.user.id)
      
      Scope.student?(scope) ->
        # Filter by enrollment or other criteria
        []
      
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

### In Your LiveViews

Always pass `current_scope` to context functions:

```elixir
def mount(_params, _session, socket) do
  assignments = Assignments.list_assignments(socket.assigns.current_scope)
  {:ok, assign(socket, assignments: assignments)}
end

def handle_event("create", %{"assignment" => attrs}, socket) do
  case Assignments.create_assignment(socket.assigns.current_scope, attrs) do
    {:ok, assignment} ->
      {:noreply, socket |> put_flash(:info, "Created!") |> push_navigate(to: ~p"/")}
    
    {:error, :unauthorized} ->
      {:noreply, put_flash(socket, :error, "Unauthorized")}
    
    {:error, changeset} ->
      {:noreply, assign(socket, form: to_form(changeset))}
  end
end
```

## 🧪 Phase 5: Write Tests

### Test User Creation with Roles

```elixir
# test/support/fixtures/accounts_fixtures.ex
def user_fixture(attrs \\ %{}) do
  {:ok, user} =
    attrs
    |> Enum.into(%{
      email: unique_user_email(),
      password: valid_user_password(),
      role: Map.get(attrs, :role, "student")
    })
    |> Tasky.Accounts.register_user()

  user
end
```

### Test Authorization

```elixir
# test/tasky_web/live/admin/user_live_test.exs
defmodule TaskyWeb.Admin.UserLiveTest do
  use TaskyWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "as admin" do
    setup do
      admin = user_fixture(%{role: "admin"})
      %{conn: log_in_user(build_conn(), admin)}
    end

    test "can access user management", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/users")
      assert html =~ "User Management"
    end
  end

  describe "as student" do
    setup do
      student = user_fixture(%{role: "student"})
      %{conn: log_in_user(build_conn(), student)}
    end

    test "cannot access user management", %{conn: conn} do
      {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/users")
    end
  end
end
```

## 🎨 Phase 6: Enhance UI (Optional)

### Add Role Badge Component

Create a reusable component for role badges:

```elixir
# In lib/tasky_web/components/core_components.ex or a new file

attr :role, :string, required: true
attr :class, :string, default: ""

def role_badge(assigns) do
  ~H"""
  <span class={[
    "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium",
    role_color(@role),
    @class
  ]}>
    {role_label(@role)}
  </span>
  """
end

defp role_color("admin"), do: "bg-purple-100 text-purple-800"
defp role_color("teacher"), do: "bg-blue-100 text-blue-800"
defp role_color("student"), do: "bg-green-100 text-green-800"
defp role_color(_), do: "bg-gray-100 text-gray-800"

defp role_label("admin"), do: "Admin"
defp role_label("teacher"), do: "Teacher"
defp role_label("student"), do: "Student"
defp role_label(_), do: "User"
```

### Enhanced Navigation

```heex
<nav class="navbar">
  <%= if @current_scope && @current_scope.user do %>
    <div class="navbar-center">
      <ul class="menu menu-horizontal px-1">
        <li><.link navigate={~p"/dashboard"}>Dashboard</.link></li>
        
        <%= if Tasky.Accounts.Scope.admin?(@current_scope) do %>
          <li><.link navigate={~p"/admin/users"}>Admin</.link></li>
        <% end %>
        
        <%= if Tasky.Accounts.Scope.admin_or_teacher?(@current_scope) do %>
          <li><.link navigate={~p"/teacher/dashboard"}>Teaching</.link></li>
        <% end %>
        
        <%= if Tasky.Accounts.Scope.student?(@current_scope) do %>
          <li><.link navigate={~p"/student/assignments"}>My Work</.link></li>
        <% end %>
      </ul>
    </div>
    
    <div class="navbar-end">
      <.role_badge role={@current_scope.user.role} />
      <.link href={~p"/users/log-out"} method="delete">Log out</.link>
    </div>
  <% end %>
</nav>
```

## 🔒 Phase 7: Production Preparation

### Security Checklist

- [ ] Change all seed user passwords
- [ ] Create real admin account with secure password
- [ ] Remove or secure test accounts
- [ ] Add audit logging for role changes
- [ ] Review all authorization checks
- [ ] Test with different roles extensively
- [ ] Add rate limiting for role change attempts
- [ ] Document role permissions for your team

### Create Production Admin

```elixir
# In production console
{:ok, admin} = Tasky.Accounts.register_user(%{
  email: "your-real-admin@yourdomain.com",
  password: "a-very-secure-password-here",
  role: "admin"
})
```

## 📚 Quick Reference

### Test Users (Development Only)

```
admin@example.com / adminpassword123
teacher@example.com / teacherpassword123
student1@example.com / studentpassword123
student2@example.com / studentpassword123
```

### Key Commands

```bash
# Run migrations
mix ecto.migrate

# Create seed users
mix run priv/repo/seeds.exs

# Start server
mix phx.server

# Open console
iex -S mix phx.server

# Run tests
mix test

# Check routes
mix phx.routes
```

### Documentation Files

- `ROLES.md` - Complete documentation
- `ROLES_QUICKSTART.md` - Quick reference
- `ROLES_CHEATSHEET.md` - Command reference
- `ROUTER_EXAMPLE.md` - Router examples
- `NAVIGATION_EXAMPLE.md` - UI examples
- `ADMIN_SETUP_EXAMPLE.md` - Admin setup
- `ROLE_SYSTEM_SUMMARY.md` - Implementation summary
- `INTEGRATION_CHECKLIST.md` - This file

## ✅ Completion Checklist

Mark off each item as you complete it:

- [ ] Phase 1: Core setup (Already done!)
- [ ] Phase 2: Added admin routes to router
- [ ] Phase 2: Tested admin user management interface
- [ ] Phase 2: Added navigation links
- [ ] Phase 3: Created teacher LiveViews (if needed)
- [ ] Phase 3: Created student LiveViews (if needed)
- [ ] Phase 4: Updated context functions with scope
- [ ] Phase 4: Updated LiveViews to pass scope
- [ ] Phase 5: Wrote authorization tests
- [ ] Phase 6: Enhanced UI with role badges
- [ ] Phase 6: Updated navigation menu
- [ ] Phase 7: Changed seed passwords
- [ ] Phase 7: Created production admin account
- [ ] Phase 7: Reviewed all authorization

## 🎉 You're Done!

Once you've completed all phases, your role-based authorization system is fully integrated.

## 🆘 Need Help?

- Review the documentation files listed above
- Check `ROLES_CHEATSHEET.md` for quick syntax
- See `ROUTER_EXAMPLE.md` for routing patterns
- Look at `lib/tasky_web/live/admin/user_live.ex` for a complete example
- Test with the provided seed users

**Happy coding!** 🚀