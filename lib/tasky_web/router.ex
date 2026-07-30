defmodule TaskyWeb.Router do
  use TaskyWeb, :router

  import TaskyWeb.UserAuth

  # Everything is served same-origin (bundled assets, local fonts, uploaded
  # images); LiveView needs the websocket, Tiptap/React need inline style
  # attributes, and content images are embedded as data:/blob: while uploading.
  @content_security_policy "default-src 'self'; " <>
                             "script-src 'self'; " <>
                             "style-src 'self' 'unsafe-inline'; " <>
                             "img-src 'self' data: blob:; " <>
                             "font-src 'self' data:; " <>
                             "connect-src 'self' ws: wss:; " <>
                             "object-src 'none'; " <>
                             "base-uri 'self'; " <>
                             "frame-ancestors 'self'; " <>
                             "form-action 'self'"

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TaskyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"content-security-policy" => @content_security_policy}
    plug :fetch_current_scope_for_user
  end

  # Served user uploads: never render as HTML/scripts, never leak referers.
  # Interim hardening while /uploads is world-readable; the real fix is the
  # private R2 bucket with presigned URLs (ROBUSTNESS_PLAN Phase 6).
  pipeline :uploads do
    plug :put_secure_browser_headers, %{
      "content-security-policy" => "default-src 'none'; sandbox",
      "cross-origin-resource-policy" => "same-origin"
    }
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

  scope "/", TaskyWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/handbook", PageController, :handbook
  end

  # Guest exam tokens are short strings — cap probing per IP (generous enough
  # for a whole class behind one school NAT).
  pipeline :guest_rate_limit do
    plug TaskyWeb.Plugs.RateLimit, bucket: :guest, limit: 300, window_ms: 60_000
  end

  ## Guest exam routes (no authentication required)

  scope "/guest", TaskyWeb.Guest do
    pipe_through [:browser, :guest_rate_limit]

    get "/exam/:exam_token/seb-config", SebController, :config
    get "/exam/:exam_token/seb-quit", SebController, :quit
    get "/exam/:exam_token/files/:field_id", FileController, :download

    live_session :guest do
      live "/enroll/:enrollment_token", EnrollLive, :enroll
      live "/exam/:exam_token", ExamLive, :show
    end
  end

  # Session-authenticated JSON API (teachers/admins only)
  scope "/api", TaskyWeb do
    pipe_through [:authenticated_api, :require_authenticated_user, :require_admin_or_teacher]

    put "/exams/:id/content", ExamContentApiController, :update

    post "/exams/:id/images", ExamImageApiController, :create

    put "/tasks/:id/content", TaskContentApiController, :update

    post "/tasks/:id/images", TaskImageApiController, :create

    put "/exams/:id/sample-solution/parts/:part_id/content",
        ExamSampleSolutionApiController,
        :update_part

    put "/exams/:id/submissions/:submission_id/parts/:part_id/content",
        ExamCorrectionContentApiController,
        :update
  end

  # Guest JSON API (token-gated via the 128-bit exam_token in the URL — not
  # brute-forceable, and autosave traffic from a whole class behind one NAT
  # would trip any sensible per-IP limit, so no rate limiting here).
  scope "/api/guest", TaskyWeb.Guest do
    pipe_through :guest_api

    put "/exam/:token/content", ExamSubmissionContentApiController, :update
  end

  # Session-authenticated JSON API for students (course learning units)
  scope "/api/student", TaskyWeb.Student do
    pipe_through [:authenticated_api, :require_authenticated_user, :require_student]

    put "/tasks/:id/answers", TaskAnswersApiController, :update
  end

  # Public serving of uploaded exam images (unguessable UUID filenames). Public
  # so the browser and Gotenberg can load <img> sources without an auth token.
  scope "/uploads", TaskyWeb do
    pipe_through :uploads

    get "/exams/:exam_id/attachments/:filename", UploadController, :attachment
    get "/exams/:exam_id/:filename", UploadController, :show
    get "/tasks/:task_id/attachments/:filename", UploadController, :task_attachment
    get "/tasks/:task_id/:filename", UploadController, :task_image
  end

  ## Task routes (Teachers and Admins only)

  scope "/", TaskyWeb do
    pipe_through [:browser, :require_authenticated_user, :require_admin_or_teacher]

    get "/exams/:id/submissions/:submission_id/files/:file_id",
        SubmissionFileController,
        :download

    get "/tasks/:id/submissions/:submission_id/files/:file_id",
        TaskSubmissionFileController,
        :download

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
      live "/progress/:task_id", TaskLive.Progress, :task_progress
      live "/tasks/:id/content", TaskLive.Content, :content

      live "/classes", ClassLive.Index, :index
      live "/classes/new", ClassLive.Form, :new
      live "/classes/:id/edit", ClassLive.Form, :edit

      live "/exams", ExamLive.Index, :index
      live "/exams/new", ExamLive.Form, :new
      live "/exams/:id", ExamLive.Show, :show
      live "/exams/:id/edit", ExamLive.Form, :edit
      live "/exams/:id/cockpit", ExamLive.Cockpit, :cockpit
      live "/exams/:id/cockpit/config", ExamLive.CockpitConfig, :config
      live "/exams/:id/correction", ExamLive.Correction, :correction

      live "/exams/:id/correction/:submission_id/parts/:part_id",
           ExamLive.CorrectionPart,
           :correction_part

      live "/exams/:id/correction/bulk/:part_id",
           ExamLive.CorrectionPartBulk,
           :correction_part_bulk

      live "/exams/:id/correction/grading", ExamLive.Grading, :grading

      live "/exams/:id/content", ExamLive.Content, :content
    end
  end

  ## Student routes

  scope "/student", TaskyWeb.Student, as: :student do
    pipe_through [:browser, :require_authenticated_user, :require_student]

    get "/tasks/:task_id/files/:field_id", FileController, :download

    live_session :student,
      on_mount: [{TaskyWeb.UserAuth, :require_student}] do
      live "/courses", CoursesLive, :index
      live "/courses/:id", CourseLive, :show
      live "/tasks/:id", TaskLive, :show
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
    end
  end

  ## Token-authenticated print views (consumed by Gotenberg's headless Chrome).
  scope "/print", TaskyWeb do
    pipe_through [:browser]

    live_session :print, layout: false do
      live "/exam-submission/:exam_id/:submission_id", ExamLive.Print, :print
    end
  end

  ## One-time download links for exported ZIPs.
  scope "/exports", TaskyWeb do
    pipe_through [:browser]

    get "/download", ExportController, :download
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
