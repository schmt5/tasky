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

  pipeline :webhook do
    plug :accepts, ["json"]
  end

  scope "/", TaskyWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Webhook endpoints (no authentication required)
  scope "/api", TaskyWeb do
    pipe_through :webhook

    post "/webhooks/tally", TallyWebhookController, :receive
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:tasky, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TaskyWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Task routes (Teachers and Admins only)

  scope "/", TaskyWeb do
    pipe_through [:browser, :require_authenticated_user, :require_admin_or_teacher]

    live_session :tasks,
      on_mount: [{TaskyWeb.UserAuth, :require_admin_or_teacher}] do
      live "/courses", CourseLive.Index, :index
      live "/courses/new", CourseLive.Form, :new
      live "/courses/:id", CourseLive.Show, :show
      live "/courses/:id/edit", CourseLive.Form, :edit
      live "/courses/:id/add", CourseLive.Add, :add
    end
  end

  ## Student routes

  scope "/student", TaskyWeb.Student, as: :student do
    pipe_through [:browser, :require_authenticated_user, :require_student]

    live_session :student,
      on_mount: [{TaskyWeb.UserAuth, :require_student}] do
      live "/courses", CoursesLive, :index
      live "/courses/:id", CourseLive, :show
      live "/tasks/:id", TaskLive, :show
      live "/my-tasks", MyTasksLive, :index
    end
  end

  ## Authentication routes

  scope "/", TaskyWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{TaskyWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end
  end

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
end
