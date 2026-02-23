# Navigation Component with Role-Based Links

This guide shows how to add role-based navigation links to your application layout.

## Option 1: Update Existing Layout

Update your `lib/tasky_web/components/layouts.ex` to include role-based navigation:

```elixir
defmodule TaskyWeb.Layouts do
  use TaskyWeb, :html
  alias Tasky.Accounts.Scope

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8 bg-base-200">
      <div class="navbar-start">
        <.link navigate={~p"/"} class="flex items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-xl font-bold">Tasky</span>
        </.link>
      </div>

      <div class="navbar-center">
        <%= if @current_scope && @current_scope.user do %>
          <ul class="menu menu-horizontal px-1 space-x-2">
            <%!-- All authenticated users --%>
            <li>
              <.link navigate={~p"/dashboard"} class="btn btn-ghost">Dashboard</.link>
            </li>

            <%!-- Admin links --%>
            <%= if Scope.admin?(@current_scope) do %>
              <li>
                <.link navigate={~p"/admin"} class="btn btn-ghost">Admin Panel</.link>
              </li>
              <li>
                <.link navigate={~p"/admin/users"} class="btn btn-ghost">Manage Users</.link>
              </li>
            <% end %>

            <%!-- Teacher links (Teachers and Admins) --%>
            <%= if Scope.admin_or_teacher?(@current_scope) do %>
              <li>
                <.link navigate={~p"/teacher/dashboard"} class="btn btn-ghost">Teaching</.link>
              </li>
              <li>
                <.link navigate={~p"/assignments/new"} class="btn btn-ghost">
                  Create Assignment
                </.link>
              </li>
            <% end %>

            <%!-- Student links --%>
            <%= if Scope.student?(@current_scope) do %>
              <li>
                <.link navigate={~p"/student/assignments"} class="btn btn-ghost">
                  My Assignments
                </.link>
              </li>
              <li>
                <.link navigate={~p"/student/grades"} class="btn btn-ghost">My Grades</.link>
              </li>
            <% end %>
          </ul>
        <% end %>
      </div>

      <div class="navbar-end space-x-2">
        <%= if @current_scope && @current_scope.user do %>
          <%!-- User menu dropdown --%>
          <div class="dropdown dropdown-end">
            <label tabindex="0" class="btn btn-ghost">
              <span class="hidden sm:inline">{@current_scope.user.email}</span>
              <.icon name="hero-user-circle" class="size-5" />
            </label>
            <ul
              tabindex="0"
              class="dropdown-content menu p-2 shadow-lg bg-base-100 rounded-box w-52 mt-4"
            >
              <li class="menu-title">
                <span>
                  Role: <%= role_badge(@current_scope.user.role) %>
                </span>
              </li>
              <li>
                <.link navigate={~p"/users/settings"}>
                  <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
                </.link>
              </li>
              <li>
                <.link navigate={~p"/profile"}>
                  <.icon name="hero-user" class="size-4" /> Profile
                </.link>
              </li>
              <li>
                <.link href={~p"/users/log-out"} method="delete">
                  <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Log out
                </.link>
              </li>
            </ul>
          </div>
        <% else %>
          <%!-- Not logged in --%>
          <.link navigate={~p"/users/log-in"} class="btn btn-ghost">Log in</.link>
          <.link navigate={~p"/users/register"} class="btn btn-primary">Register</.link>
        <% end %>

        <.theme_toggle />
      </div>
    </header>

    <main class="px-4 py-8 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-7xl">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  # Helper function for role badge
  defp role_badge("admin"), do: "Admin 👑"
  defp role_badge("teacher"), do: "Teacher 📚"
  defp role_badge("student"), do: "Student 🎓"
  defp role_badge(_), do: "User"

  # ... rest of your existing functions
end
```

## Option 2: Separate Navigation Component

Create a dedicated navigation component:

```elixir
# lib/tasky_web/components/navigation.ex
defmodule TaskyWeb.Navigation do
  use Phoenix.Component
  import TaskyWeb.CoreComponents
  alias Tasky.Accounts.Scope

  attr :current_scope, :map, default: nil
  attr :current_path, :string, default: "/"

  def nav_bar(assigns) do
    ~H"""
    <nav class="bg-white shadow-sm border-b border-gray-200">
      <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div class="flex h-16 justify-between items-center">
          <%!-- Logo --%>
          <div class="flex items-center">
            <.link navigate={~p"/"} class="flex items-center gap-2">
              <img src={~p"/images/logo.svg"} width="32" class="h-8 w-8" />
              <span class="text-xl font-bold text-gray-900">Tasky</span>
            </.link>
          </div>

          <%!-- Main Navigation --%>
          <%= if @current_scope && @current_scope.user do %>
            <div class="hidden md:flex md:items-center md:space-x-4">
              <.nav_link navigate={~p"/dashboard"} current_path={@current_path}>
                Dashboard
              </.nav_link>

              <%= if Scope.admin?(@current_scope) do %>
                <.nav_link navigate={~p"/admin"} current_path={@current_path}>
                  Admin
                </.nav_link>
              <% end %>

              <%= if Scope.admin_or_teacher?(@current_scope) do %>
                <.nav_link navigate={~p"/teacher/dashboard"} current_path={@current_path}>
                  Teaching
                </.nav_link>
              <% end %>

              <%= if Scope.student?(@current_scope) do %>
                <.nav_link navigate={~p"/student/assignments"} current_path={@current_path}>
                  Assignments
                </.nav_link>
              <% end %>
            </div>

            <%!-- User Menu --%>
            <div class="flex items-center space-x-4">
              <.role_badge role={@current_scope.user.role} />
              
              <.link navigate={~p"/users/settings"} class="text-gray-700 hover:text-gray-900">
                <.icon name="hero-cog-6-tooth" class="h-6 w-6" />
              </.link>

              <.link
                href={~p"/users/log-out"}
                method="delete"
                class="text-gray-700 hover:text-gray-900"
              >
                <.icon name="hero-arrow-right-on-rectangle" class="h-6 w-6" />
              </.link>
            </div>
          <% else %>
            <div class="flex items-center space-x-4">
              <.link navigate={~p"/users/log-in"} class="text-gray-700 hover:text-gray-900">
                Log in
              </.link>
              <.link
                navigate={~p"/users/register"}
                class="rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white hover:bg-indigo-500"
              >
                Register
              </.link>
            </div>
          <% end %>
        </div>
      </div>
    </nav>
    """
  end

  attr :navigate, :string, required: true
  attr :current_path, :string, default: "/"
  slot :inner_block, required: true

  defp nav_link(assigns) do
    assigns =
      assign(assigns, :active?, String.starts_with?(assigns.current_path, assigns.navigate))

    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "px-3 py-2 rounded-md text-sm font-medium transition-colors",
        if(@active?,
          do: "bg-indigo-100 text-indigo-700",
          else: "text-gray-700 hover:bg-gray-100 hover:text-gray-900"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :role, :string, required: true

  defp role_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium",
      role_colors(@role)
    ]}>
      {role_label(@role)}
    </span>
    """
  end

  defp role_colors("admin"), do: "bg-purple-100 text-purple-800"
  defp role_colors("teacher"), do: "bg-blue-100 text-blue-800"
  defp role_colors("student"), do: "bg-green-100 text-green-800"
  defp role_colors(_), do: "bg-gray-100 text-gray-800"

  defp role_label("admin"), do: "Admin"
  defp role_label("teacher"), do: "Teacher"
  defp role_label("student"), do: "Student"
  defp role_label(_), do: "User"
end
```

Then use it in your layout:

```elixir
# In lib/tasky_web/components/layouts.ex
defmodule TaskyWeb.Layouts do
  use TaskyWeb, :html
  alias TaskyWeb.Navigation

  def app(assigns) do
    ~H"""
    <Navigation.nav_bar current_scope={@current_scope} current_path={@conn.request_path || "/"} />
    
    <main class="px-4 py-8 sm:px-6 lg:px-8">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end
end
```

## Option 3: Sidebar Navigation

For apps with more navigation options:

```elixir
# lib/tasky_web/components/sidebar.ex
defmodule TaskyWeb.Sidebar do
  use Phoenix.Component
  import TaskyWeb.CoreComponents
  alias Tasky.Accounts.Scope

  attr :current_scope, :map, default: nil
  attr :current_path, :string, default: "/"

  def sidebar(assigns) do
    ~H"""
    <aside class="w-64 bg-gray-900 min-h-screen text-white">
      <div class="p-4">
        <.link navigate={~p"/"} class="flex items-center gap-2 mb-8">
          <img src={~p"/images/logo.svg"} width="32" class="h-8 w-8" />
          <span class="text-xl font-bold">Tasky</span>
        </.link>

        <%= if @current_scope && @current_scope.user do %>
          <%!-- User Info --%>
          <div class="mb-6 p-3 bg-gray-800 rounded-lg">
            <div class="text-sm font-medium truncate">{@current_scope.user.email}</div>
            <div class="text-xs text-gray-400 mt-1">
              {role_label(@current_scope.user.role)}
            </div>
          </div>

          <nav class="space-y-1">
            <%!-- Common Links --%>
            <.sidebar_link navigate={~p"/dashboard"} current_path={@current_path} icon="hero-home">
              Dashboard
            </.sidebar_link>

            <%!-- Admin Section --%>
            <%= if Scope.admin?(@current_scope) do %>
              <div class="mt-6">
                <div class="px-3 text-xs font-semibold text-gray-400 uppercase tracking-wider">
                  Admin
                </div>
                <.sidebar_link
                  navigate={~p"/admin/users"}
                  current_path={@current_path}
                  icon="hero-users"
                >
                  Manage Users
                </.sidebar_link>
                <.sidebar_link
                  navigate={~p"/admin/reports"}
                  current_path={@current_path}
                  icon="hero-chart-bar"
                >
                  Reports
                </.sidebar_link>
              </div>
            <% end %>

            <%!-- Teacher Section --%>
            <%= if Scope.admin_or_teacher?(@current_scope) do %>
              <div class="mt-6">
                <div class="px-3 text-xs font-semibold text-gray-400 uppercase tracking-wider">
                  Teaching
                </div>
                <.sidebar_link
                  navigate={~p"/teacher/dashboard"}
                  current_path={@current_path}
                  icon="hero-academic-cap"
                >
                  Teaching Dashboard
                </.sidebar_link>
                <.sidebar_link
                  navigate={~p"/assignments"}
                  current_path={@current_path}
                  icon="hero-document-text"
                >
                  Assignments
                </.sidebar_link>
                <.sidebar_link
                  navigate={~p"/teacher/students"}
                  current_path={@current_path}
                  icon="hero-user-group"
                >
                  Students
                </.sidebar_link>
              </div>
            <% end %>

            <%!-- Student Section --%>
            <%= if Scope.student?(@current_scope) do %>
              <div class="mt-6">
                <div class="px-3 text-xs font-semibold text-gray-400 uppercase tracking-wider">
                  Student
                </div>
                <.sidebar_link
                  navigate={~p"/student/assignments"}
                  current_path={@current_path}
                  icon="hero-document-text"
                >
                  My Assignments
                </.sidebar_link>
                <.sidebar_link
                  navigate={~p"/student/grades"}
                  current_path={@current_path}
                  icon="hero-chart-bar"
                >
                  My Grades
                </.sidebar_link>
              </div>
            <% end %>

            <%!-- Bottom Links --%>
            <div class="mt-6 pt-6 border-t border-gray-700">
              <.sidebar_link
                navigate={~p"/users/settings"}
                current_path={@current_path}
                icon="hero-cog-6-tooth"
              >
                Settings
              </.sidebar_link>
              <.sidebar_link
                href={~p"/users/log-out"}
                method="delete"
                icon="hero-arrow-right-on-rectangle"
              >
                Log out
              </.sidebar_link>
            </div>
          </nav>
        <% end %>
      </div>
    </aside>
    """
  end

  attr :navigate, :string, default: nil
  attr :href, :string, default: nil
  attr :method, :string, default: "get"
  attr :current_path, :string, default: "/"
  attr :icon, :string, default: nil
  slot :inner_block, required: true

  defp sidebar_link(assigns) do
    path = assigns.navigate || assigns.href
    assigns = assign(assigns, :active?, path && String.starts_with?(assigns.current_path, path))

    ~H"""
    <%= if @navigate do %>
      <.link
        navigate={@navigate}
        class={[
          "flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors",
          if(@active?,
            do: "bg-indigo-600 text-white",
            else: "text-gray-300 hover:bg-gray-800 hover:text-white"
          )
        ]}
      >
        <.icon :if={@icon} name={@icon} class="size-5" />
        {render_slot(@inner_block)}
      </.link>
    <% else %>
      <.link
        href={@href}
        method={@method}
        class="flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium text-gray-300 hover:bg-gray-800 hover:text-white transition-colors"
      >
        <.icon :if={@icon} name={@icon} class="size-5" />
        {render_slot(@inner_block)}
      </.link>
    <% end %>
    """
  end

  defp role_label("admin"), do: "Administrator"
  defp role_label("teacher"), do: "Teacher"
  defp role_label("student"), do: "Student"
  defp role_label(_), do: "User"
end
```

## Mobile Navigation

Add responsive mobile menu:

```heex
<%!-- Mobile menu button --%>
<button
  class="md:hidden inline-flex items-center justify-center p-2 rounded-md text-gray-700 hover:text-gray-900 hover:bg-gray-100"
  phx-click={JS.toggle(to: "#mobile-menu")}
>
  <.icon name="hero-bars-3" class="size-6" />
</button>

<%!-- Mobile menu (hidden by default) --%>
<div id="mobile-menu" class="hidden md:hidden">
  <div class="space-y-1 px-2 pb-3 pt-2">
    <.link navigate={~p"/dashboard"} class="block px-3 py-2 rounded-md text-base font-medium">
      Dashboard
    </.link>
    
    <%= if Scope.admin?(@current_scope) do %>
      <.link navigate={~p"/admin"} class="block px-3 py-2 rounded-md text-base font-medium">
        Admin
      </.link>
    <% end %>
    
    <%= if Scope.admin_or_teacher?(@current_scope) do %>
      <.link navigate={~p"/teacher/dashboard"} class="block px-3 py-2 rounded-md text-base font-medium">
        Teaching
      </.link>
    <% end %>
    
    <%= if Scope.student?(@current_scope) do %>
      <.link navigate={~p"/student/assignments"} class="block px-3 py-2 rounded-md text-base font-medium">
        My Assignments
      </.link>
    <% end %>
  </div>
</div>
```

## Testing Navigation

```elixir
# test/tasky_web/components/navigation_test.exs
defmodule TaskyWeb.NavigationTest do
  use TaskyWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "navigation for admin" do
    setup do
      admin = user_fixture(%{role: "admin"})
      %{admin: admin}
    end

    test "shows admin links", %{conn: conn, admin: admin} do
      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      
      assert html =~ "Admin Panel"
      assert html =~ "Manage Users"
    end
  end

  describe "navigation for student" do
    setup do
      student = user_fixture(%{role: "student"})
      %{student: student}
    end

    test "does not show admin links", %{conn: conn, student: student} do
      conn = log_in_user(conn, student)
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      
      refute html =~ "Admin Panel"
      assert html =~ "My Assignments"
    end
  end
end
```

## Summary

Choose the navigation pattern that fits your needs:
- **Option 1**: Simple inline navigation in layout
- **Option 2**: Separate component for reusability
- **Option 3**: Sidebar for complex apps

All options support:
✅ Role-based link visibility
✅ Active link highlighting
✅ User role badges
✅ Responsive design
✅ Easy testing