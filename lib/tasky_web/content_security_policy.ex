defmodule TaskyWeb.ContentSecurityPolicy do
  @moduledoc """
  The page CSP, built at runtime because one source depends on the configured
  storage adapter.

  With `Tasky.Storage.R2`, `/uploads/...` answers with a 302 onto the bucket's
  presigned-URL origin. CSP re-checks the redirect target against the source
  list, so that origin has to be in `img-src` or the browser blocks every
  content image — the request reaches the app and returns a healthy 302, and
  the image still renders as a broken icon. The same applies to the
  token-authenticated print views: Gotenberg's Chrome enforces CSP too, so
  without this the PDF export loses its images as well.
  """

  @directives [
    {"default-src", ["'self'"]},
    {"script-src", ["'self'"]},
    {"style-src", ["'self'", "'unsafe-inline'"]},
    {"font-src", ["'self'", "data:"]},
    {"connect-src", ["'self'", "ws:", "wss:"]},
    {"object-src", ["'none'"]},
    {"base-uri", ["'self'"]},
    {"frame-ancestors", ["'self'"]},
    {"form-action", ["'self'"]}
  ]

  # blob: covers the client-side previews the editor renders before an upload
  # has been stored; data: covers inlined icons.
  @img_src ["'self'", "data:", "blob:"]

  @doc "Header value for the `:browser` pipeline."
  def page do
    [{"img-src", @img_src ++ storage_origins()} | @directives]
    |> Enum.map_join("; ", fn {directive, sources} ->
      Enum.join([directive | sources], " ")
    end)
  end

  @doc """
  Origins the app itself loads content from, besides its own.

  Shared with the Safe Exam Browser URL filter
  (`Tasky.Exams.SebConfig`): SEB enforces its own allow-list on top of the
  CSP, so an origin missing there fails exactly the same way — the request
  reaches the app, returns a healthy 302, and the image renders as a broken
  icon. Deriving both lists from this one function is what stops them
  diverging the next time a storage adapter is added.
  """
  @spec storage_origins() :: [String.t()]
  # Only the remote adapter serves uploads off another origin; the local one
  # streams the bytes itself and stays covered by 'self'.
  def storage_origins do
    case Application.get_env(:tasky, :storage_adapter, Tasky.Storage.Local) do
      Tasky.Storage.R2 -> [Tasky.Storage.R2.endpoint_url()]
      _ -> []
    end
  end
end
