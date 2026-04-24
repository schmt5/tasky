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

  # Session-authenticated JSON API (for React components on authenticated pages)
  pipeline :authenticated_api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :fetch_current_scope_for_user
  end

  # Guest JSON API (CSRF-protected, no user auth — access gated by exam token)
  pipeline :guest_api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
  end

  pipeline :webhook do
    plug :accepts, ["json"]
  end

  scope "/", TaskyWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  ## Guest exam routes (no authentication required)

  scope "/guest", TaskyWeb.Guest do
    pipe_through [:browser]

    live_session :guest do
      live "/enroll/:enrollment_token", EnrollLive, :enroll
      live "/exam/:exam_token", ExamLive, :show
    end
  end

  # Webhook endpoints (no authentication required)
  scope "/api", TaskyWeb do
    pipe_through :webhook

    post "/webhooks/tally", TallyWebhookController, :receive
  end

  # Session-authenticated JSON API (teachers/admins only)
  scope "/api", TaskyWeb do
    pipe_through [:authenticated_api, :require_authenticated_user, :require_admin_or_teacher]

    put "/exams/:id/content", ExamContentApiController, :update
  end

  # Guest JSON API (token-gated via exam_token in URL)
  scope "/api/guest", TaskyWeb.Guest do
    pipe_through :guest_api

    put "/exam/:token/content", ExamSubmissionContentApiController, :update
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
      live "/courses/:id/progress", CourseLive.Progress, :progress
      live "/courses/:id/students", CourseLive.Students, :students
      live "/courses/:id/reorder", CourseLive.Reorder, :reorder
      live "/courses/:id/export", CourseLive.Export, :export
      live "/progress/:task_id", TaskLive.Progress, :task_progress

      live "/classes", ClassLive.Index, :index
      live "/classes/new", ClassLive.Form, :new
      live "/classes/:id/edit", ClassLive.Form, :edit

      live "/exams", ExamLive.Index, :index
      live "/exams/new", ExamLive.Form, :new
      live "/exams/:id", ExamLive.Show, :show
      live "/exams/:id/edit", ExamLive.Form, :edit
      live "/exams/:id/cockpit", ExamLive.Cockpit, :cockpit
      live "/exams/:id/content", ExamLive.Content, :content
    end

    live_session :teacher_settings,
      on_mount: [{TaskyWeb.UserAuth, :require_admin_or_teacher}] do
      live "/settings/tally", UserLive.TallySettings, :edit
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

  ## Admin routes

  scope "/admin", TaskyWeb.Admin do
    pipe_through [:browser, :require_authenticated_user, :require_admin]

    live_session :admin,
      on_mount: [{TaskyWeb.UserAuth, :require_admin}] do
      live "/users", UserLive, :index
      live "/users/:id/edit", UserEditLive, :edit
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
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
