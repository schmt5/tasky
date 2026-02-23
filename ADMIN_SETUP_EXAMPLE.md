# Admin Setup Example - Quick Integration Guide

This guide shows you how to quickly add the admin user management interface to your router.

## Step 1: Add Admin Route to Router

Open `lib/tasky_web/router.ex` and add the following admin scope:

```elixir
defmodule TaskyWeb.Router do
  use TaskyWeb, :router

  import TaskyWeb.UserAuth

  # ... existing pipelines ...

  # ... existing routes ...

  ## Admin routes - Add this section

  scope "/admin", TaskyWeb.Admin, as: :admin do
    pipe_through [:browser, :require_authenticated_user, :require_admin]

    live_session :admin,
      on_mount: [{TaskyWeb.UserAuth, :require_admin}] do
      live "/users", UserLive, :index
    end
  end

  # ... rest of your routes ...
end
```

## Step 2: Test the Admin Interface

1. **Start your server:**
   ```bash
   mix phx.server
   ```

2. **Create or use an admin account:**
   
   If you ran the seeds:
   - Email: `admin@example.com`
   - Password: `adminpassword123`

   Or create one via IEx:
   ```bash
   iex -S mix phx.server
   ```
   
   Then:
   ```elixir
   {:ok, admin} = Tasky.Accounts.register_user(%{
     email: "youradmin@example.com",
     password: "yourpassword123",
     role: "admin"
   })
   ```

3. **Log in and visit:** `http://localhost:4000/admin/users`

## Step 3: Update Navigation (Optional)

Add a link to the admin panel in your navigation. For example, in `lib/tasky_web/components/layouts.ex`:

```heex
<%= if @current_scope && Tasky.Accounts.Scope.admin?(@current_scope) do %>
  <.link navigate={~p"/admin/users"} class="btn btn-ghost">
    Manage Users
  </.link>
<% end %>
```

## What You'll See

The admin user management page displays:

- **All users grouped by role** (Admins, Teachers, Students)
- **Email addresses**
- **Role badges** (color-coded)
- **Confirmation status**
- **Role change dropdown** (except for current user)
- **Update button** for each user

## Using the Interface

### Change a User's Role

1. Select the new role from the dropdown next to the user
2. Click "Update"
3. The page refreshes with the updated role

### View All Users

The interface automatically organizes users by role:
- **Admins** section (purple badges)
- **Teachers** section (blue badges)
- **Students** section (green badges)

## Testing Authorization

To verify the authorization is working:

1. **As Admin:** Navigate to `/admin/users` → Should work ✅
2. **As Teacher:** Navigate to `/admin/users` → Should redirect with error ❌
3. **As Student:** Navigate to `/admin/users` → Should redirect with error ❌
4. **Not logged in:** Navigate to `/admin/users` → Should redirect to login ❌

## Customizing the Admin Page

The admin user management LiveView is at `lib/tasky_web/live/admin/user_live.ex`.

You can customize:
- Table columns
- Styling
- Permissions (currently admins can't change their own role)
- Add user deletion
- Add user creation form
- Add email confirmation resend

### Example: Add User Deletion

```elixir
# In lib/tasky_web/live/admin/user_live.ex

def handle_event("delete_user", %{"user-id" => user_id}, socket) do
  user = Accounts.get_user!(user_id)
  
  # Don't allow deleting yourself
  if user.id != socket.assigns.current_scope.user.id do
    {:ok, _} = Accounts.delete_user(user)
    users_by_role = Accounts.list_all_users_grouped_by_role()
    
    {:noreply,
     socket
     |> put_flash(:info, "User deleted successfully")
     |> assign(:users_by_role, users_by_role)}
  else
    {:noreply, put_flash(socket, :error, "You cannot delete yourself")}
  end
end
```

Then add a delete button in the template:

```heex
<.button 
  phx-click="delete_user" 
  phx-value-user-id={user.id}
  data-confirm="Are you sure?">
  Delete
</.button>
```

## Complete Router Example

Here's a complete router with admin, teacher, and student sections:

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

  # Public routes
  scope "/", TaskyWeb do
    pipe_through :browser
    get "/", PageController, :home
  end

  # Authentication routes
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

  # Authenticated user settings
  scope "/", TaskyWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{TaskyWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  # ADMIN ROUTES - Admins only
  scope "/admin", TaskyWeb.Admin, as: :admin do
    pipe_through [:browser, :require_authenticated_user, :require_admin]

    live_session :admin,
      on_mount: [{TaskyWeb.UserAuth, :require_admin}] do
      live "/users", UserLive, :index
    end
  end

  # TEACHER ROUTES - Teachers and Admins
  # scope "/teacher", TaskyWeb.Teacher, as: :teacher do
  #   pipe_through [:browser, :require_authenticated_user, :require_admin_or_teacher]
  #
  #   live_session :teacher,
  #     on_mount: [{TaskyWeb.UserAuth, :require_admin_or_teacher}] do
  #     live "/dashboard", DashboardLive, :index
  #   end
  # end

  # STUDENT ROUTES - Students only
  # scope "/student", TaskyWeb.Student, as: :student do
  #   pipe_through [:browser, :require_authenticated_user, :require_student]
  #
  #   live_session :student,
  #     on_mount: [{TaskyWeb.UserAuth, :require_student}] do
  #     live "/dashboard", DashboardLive, :index
  #   end
  # end

  # Development routes
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

## Next Steps

1. ✅ Add admin route to router (shown above)
2. ✅ Log in as admin and test `/admin/users`
3. ✅ Add navigation link for admins
4. 📝 Create teacher and student routes as needed
5. 📝 Add more admin functionality (reports, settings, etc.)
6. 📝 Write tests for admin authorization

## Security Notes

- ✅ Route is protected by `:require_admin` plug AND `on_mount` callback
- ✅ Admins cannot change their own role (prevents lockout)
- ✅ Only admins can access this page
- ⚠️ Remember to change seed passwords in production
- ⚠️ Consider adding audit logging for role changes

## Troubleshooting

### "You must be an admin to access this page"

**Solution:** Check your user's role:
```elixir
# In IEx
user = Tasky.Accounts.get_user_by_email("your@email.com")
IO.inspect(user.role)

# If not admin, update it:
Tasky.Accounts.update_user_role(user, %{role: "admin"})
```

### Page not found (404)

**Solution:** Make sure you added the admin scope to your router.

### Route warnings on compile

**Solution:** These are expected if you haven't added the routes yet. They're just warnings, not errors.

### Can't see role changes

**Solution:** Make sure the form has the correct phx attributes:
- `phx-submit="change_role"`
- `phx-value-user-id={user.id}`

## Summary

You now have:
- ✅ Admin user management interface
- ✅ Role-based authorization working
- ✅ Visual role badges
- ✅ Role changing functionality
- ✅ Protection against self-modification

For more details, see:
- `ROLES.md` - Complete documentation
- `ROLES_QUICKSTART.md` - Quick reference
- `ROUTER_EXAMPLE.md` - More router examples
- `NAVIGATION_EXAMPLE.md` - Navigation examples