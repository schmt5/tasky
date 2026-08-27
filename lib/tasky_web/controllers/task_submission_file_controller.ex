defmodule TaskyWeb.TaskSubmissionFileController do
  @moduledoc """
  Lets teachers/admins download a student's uploaded answer file for a
  learning unit (task), or view one inline. The task is resolved through the
  caller's scope, so teachers only reach their own tasks.
  """
  use TaskyWeb, :controller

  import TaskyWeb.StorageServing

  alias Tasky.Tasks
  alias Tasky.Uploads

  # Types the file overview offers an "open" action for. Everything else is
  # download-only: this route answers on the app's own origin (pipeline
  # `:browser`), so serving arbitrary uploaded bytes inline would be an XSS
  # vector — the reason the hardened `:uploads` pipeline exists at all.
  @inline_content_types ~w(image/jpeg image/png application/pdf)

  def download(conn, params) do
    with {:ok, task, submission, file} <- resolve(conn, params),
         {:ok, source} <- fetch(task, submission, file, {"attachment", file.original_name}) do
      serve_download(conn, source, file.original_name, file.content_type)
    else
      _ -> not_found(conn)
    end
  end

  def inline(conn, params) do
    with {:ok, task, submission, file} <- resolve(conn, params),
         true <- file.content_type in @inline_content_types,
         {:ok, source} <- fetch(task, submission, file, "inline") do
      conn
      |> harden(file.content_type)
      |> serve_inline(source, file.content_type, cache_control: "private, no-store")
    else
      _ -> not_found(conn)
    end
  end

  defp resolve(conn, %{"id" => task_id, "submission_id" => submission_id, "file_id" => file_id}) do
    task = Tasks.get_task!(conn.assigns.current_scope, task_id)

    with submission when not is_nil(submission) <- Tasks.get_submission(task, submission_id),
         file when not is_nil(file) <- Tasks.get_submission_file_by_id(submission, file_id) do
      {:ok, task, submission, file}
    end
  end

  defp fetch(task, submission, file, disposition) do
    Uploads.fetch_task_submission_file(task.id, submission.id, file.stored_filename,
      disposition: disposition,
      content_type: file.content_type
    )
  end

  # An inline image gets the `:uploads` pipeline's policy: nothing may load,
  # and `sandbox` keeps it from acting in the app's origin.
  #
  # A PDF drops `sandbox` and adds `object-src 'self'`, because a browser's
  # built-in PDF viewer runs as a plugin object and a policy that blocks it
  # makes the browser download the file instead of showing it. Neither
  # concession widens what the bytes can do — the response is a PDF under a
  # pinned content type with `nosniff`, not a document that could embed
  # anything. Untested end to end: the in-app preview browser has no PDF
  # viewer and downloads every PDF regardless of headers.
  defp harden(conn, "application/pdf"), do: csp(conn, "default-src 'none'; object-src 'self'")
  defp harden(conn, _image), do: csp(conn, "default-src 'none'; sandbox")

  defp csp(conn, policy) do
    conn
    |> put_resp_header("content-security-policy", policy)
    |> put_resp_header("x-content-type-options", "nosniff")
  end

  defp not_found(conn), do: conn |> put_status(:not_found) |> text("Not found")
end
