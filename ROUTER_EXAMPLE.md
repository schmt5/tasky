# Router Configuration Examples with Role-Based Authorization

This file shows example router configurations for implementing role-based authorization in your Phoenix application.

## Complete Router Example

Here's how to structure your router with role-based authorization:

```elixir
defmodule TaskyWeb.Router do
  use TaskyWeb, :router

  import TaskyWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TaskyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Public routes (no authentication required)
  scope "/", TaskyWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # ============================================================================
  # AUTHENTICATION ROUTES
  # ============================================================================

  scope "/", TaskyWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{TaskyWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  scope "/", TaskyWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{TaskyWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  # ============================================================================
  # ADMIN ROUTES (Admin only)
  # ============================================================================

  scope "/admin", TaskyWeb.Admin, as: :admin do
    pipe_through [:browser, :require_authenticated_user, :require_admin]

    live_session :admin,
      on_mount: [{TaskyWeb.UserAuth, :require_admin}] do
      live "/", DashboardLive, :index
      live "/users", UserLive, :index
      live "/users/:id", UserLive, :show
      live "/reports", ReportLive, :index
    end
  end

  # ============================================================================
  # TEACHER ROUTES (Teachers and Admins)
  # ============================================================================

  scope "/teacher", TaskyWeb.Teacher, as: :teacher do
    pipe_through [:browser, :require_authenticated_user, :require_admin_or_teacher]

    live_session :teacher,
      on_mount: [{TaskyWeb.UserAuth, :require_admin_or_teacher}] do
      live "/", DashboardLive, :index
      live "/assignments", AssignmentLive, :index
      live "/assignments/new", AssignmentLive, :new
      live "/assignments/:id/edit", AssignmentLive, :edit
      live "/students", StudentLive, :index
      live "/grades", GradeLive, :index
    end
  end

  # ============================================================================
  # STUDENT ROUTES (Students only)
  # ============================================================================

  scope "/student", TaskyWeb.Student, as: :student do
    pipe_through [:browser, :require_authenticated_user, :require_student]

    live_session :student,
      on_mount: [{TaskyWeb.UserAuth, :require_student}] do
      live "/", DashboardLive, :index
      live "/assignments", AssignmentLive, :index
      live "/assignments/:id", AssignmentLive, :show
      live "/grades", GradeLive, :index
    end
  end

  # ============================================================================
  # SHARED AUTHENTICATED ROUTES (All authenticated users)
  # ============================================================================

  scope "/", TaskyWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated,
      on_mount: [{TaskyWeb.UserAuth, :require_authenticated}] do
      live "/dashboard", DashboardLive, :index
      live "/profile", ProfileLive, :show
      live "/profile/edit", ProfileLive, :edit
    end
  end

  # ============================================================================
  # API ROUTES (if needed)
  # ============================================================================

  # scope "/api", TaskyWeb do
  #   pipe_through :api
  # end

  # ============================================================================
  # DEVELOPMENT ROUTES
  # ============================================================================

  if Application.compile_env(:tasky, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TaskyWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
```

## Alternative: Shared Assignment Routes

If you want assignments accessible to all authenticated users but with different permissions:

```elixir
scope "/assignments", TaskyWeb do
  pipe_through [:browser, :require_authenticated_user]

  # All authenticated users can view assignments
  live_session :assignments_read,
    on_mount: [{TaskyWeb.UserAuth, :require_authenticated}] do
    live "/", AssignmentLive.Index, :index
    live "/:id", AssignmentLive.Show, :show
  end

  # Only teachers and admins can create/edit assignments
  live_session :assignments_write,
    on_mount: [{TaskyWeb.UserAuth, :require_admin_or_teacher}] do
    live "/new", AssignmentLive.Form, :new
    live "/:id/edit", AssignmentLive.Form, :edit
  end
end
```

## Controller-Based Routes Example

For traditional controller actions:

```elixir
scope "/admin", TaskyWeb.Admin, as: :admin do
  pipe_through [:browser, :require_authenticated_user, :require_admin]

  # Controller routes
  resources "/reports", ReportController, only: [:index, :show]
  post "/reports/:id/generate", ReportController, :generate
  get "/analytics", AnalyticsController, :index
end

scope "/teacher", TaskyWeb.Teacher, as: :teacher do
  pipe_through [:browser, :require_authenticated_user, :require_admin_or_teacher]

  resources "/classes", ClassController
  post "/assignments/:id/grade", AssignmentController, :grade
end
```

## Key Points

### 1. Pipeline Order Matters

```elixir
pipe_through [:browser, :require_authenticated_user, :require_admin]
```

The order is:
1. `:browser` - Sets up basic browser functionality
2. `:require_authenticated_user` - Ensures user is logged in
3. `:require_admin` - Ensures user has admin role

### 2. Live Session Names Must Be Unique

❌ **Wrong** - Duplicate live_session names:
```elixir
scope "/admin" do
  live_session :admin, on_mount: [...] do
    live "/users", UserLive, :index
  end
end

scope "/teacher" do
  live_session :admin, on_mount: [...] do  # ❌ Same name!
    live "/classes", ClassLive, :index
  end
end
```

✅ **Correct** - Unique live_session names:
```elixir
scope "/admin" do
  live_session :admin, on_mount: [...] do
    live "/users", UserLive, :index
  end
end

scope "/teacher" do
  live_session :teacher, on_mount: [...] do
    live "/classes", ClassLive, :index
  end
end
```

### 3. Always Match Plugs with on_mount

Keep authorization consistent:

```elixir
scope "/admin" do
  pipe_through [:browser, :require_authenticated_user, :require_admin]
  
  live_session :admin,
    on_mount: [{TaskyWeb.UserAuth, :require_admin}] do
    # Routes here
  end
end
```

Both the `:require_admin` plug and `:require_admin` on_mount callback ensure admin access.

### 4. Use `as:` for Route Helpers

```elixir
scope "/admin", TaskyWeb.Admin, as: :admin do
  live_session :admin, on_mount: [...] do
    live "/users", UserLive, :index  # Helper: ~p"/admin/users"
  end
end
```

## Testing Your Routes

After updating your router, test each route:

### 1. Start the server
```bash
mix phx.server
```

### 2. Create test users (if not already created)
```elixir
# In IEx: iex -S mix phx.server
alias Tasky.Accounts

{:ok, admin} = Accounts.register_user(%{
  email: "admin@test.com",
  password: "adminpass123456",
  role: "admin"
})

{:ok, teacher} = Accounts.register_user(%{
  email: "teacher@test.com",
  password: "teacherpass123456",
  role: "teacher"
})

{:ok, student} = Accounts.register_user(%{
  email: "student@test.com",
  password: "studentpass123456",
  role: "student"
})
```

### 3. Test authorization
- Visit `/admin` as student → Should redirect with error
- Visit `/admin` as admin → Should work
- Visit `/teacher` as student → Should redirect with error
- Visit `/teacher` as teacher → Should work

## Common Patterns

### Pattern 1: Role-Specific Dashboards

```elixir
# Each role gets their own dashboard route
scope "/admin", TaskyWeb.Admin do
  live_session :admin, on_mount: [{TaskyWeb.UserAuth, :require_admin}] do
    live "/dashboard", DashboardLive, :index
  end
end

scope "/teacher", TaskyWeb.Teacher do
  live_session :teacher, on_mount: [{TaskyWeb.UserAuth, :require_admin_or_teacher}] do
    live "/dashboard", DashboardLive, :index
  end
end

scope "/student", TaskyWeb.Student do
  live_session :student, on_mount: [{TaskyWeb.UserAuth, :require_student}] do
    live "/dashboard", DashboardLive, :index
  end
end
```

### Pattern 2: Shared Resources with Different Access

```elixir
scope "/assignments", TaskyWeb do
  pipe_through [:browser, :require_authenticated_user]

  # Everyone can read
  live_session :assignments_read,
    on_mount: [{TaskyWeb.UserAuth, :require_authenticated}] do
    live "/", AssignmentLive.Index, :index
    live "/:id", AssignmentLive.Show, :show
  end
end

# Only teachers/admins can write
scope "/assignments", TaskyWeb do
  pipe_through [:browser, :require_authenticated_user, :require_admin_or_teacher]

  live_session :assignments_write,
    on_mount: [{TaskyWeb.UserAuth, :require_admin_or_teacher}] do
    live "/new", AssignmentLive.Form, :new
    live "/:id/edit", AssignmentLive.Form, :edit
  end
end
```

### Pattern 3: API Routes with Role Protection

```elixir
pipeline :api_auth do
  plug :accepts, ["json"]
  plug :fetch_current_scope_for_user
  plug :require_authenticated_user
end

scope "/api/admin", TaskyWeb.Api.Admin, as: :api_admin do
  pipe_through [:api_auth, :require_admin]
  
  resources "/users", UserController, only: [:index, :show, :update]
  get "/stats", StatsController, :index
end

scope "/api/teacher", TaskyWeb.Api.Teacher, as: :api_teacher do
  pipe_through [:api_auth, :require_admin_or_teacher]
  
  resources "/assignments", AssignmentController
  post "/assignments/:id/grade", AssignmentController, :grade
end
```

## Debugging Routes

If routes aren't working:

1. **Check route compilation**:
   ```bash
   mix phx.routes
   ```

2. **Check authorization**:
   ```bash
   mix phx.routes | grep "/admin"
   ```

3. **Verify user role in IEx**:
   ```elixir
   user = Tasky.Accounts.get_user_by_email("user@example.com")
   user.role
   ```

4. **Check current_scope**:
   In your LiveView, add temporary debug:
   ```elixir
   def mount(_params, _session, socket) do
     IO.inspect(socket.assigns.current_scope, label: "CURRENT SCOPE")
     {:ok, socket}
   end
   ```

## Next Steps

1. Update your `router.ex` with the routes you need
2. Create the corresponding LiveView modules
3. Add navigation links in your layout
4. Write tests for each role's access
5. See `ROLES.md` for complete authorization documentation