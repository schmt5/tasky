defmodule Tasky.Storage do
  @moduledoc """
  Behaviour for stored file bytes (content images, teacher attachments,
  student submission files) — the seam the R2 cutover plugs into
  (docs/ROBUSTNESS_PLAN.md Phases 4.1/6).

  Keys are slash-joined segment paths (`"exams/42/attachments/<uuid>.pdf"`);
  segment validation is the caller's job (`Tasky.Uploads`). `fetch/1`
  returns how to serve the object: a local file to `send_file`, or a URL to
  302-redirect to (a short-lived presigned GET on R2).
  """

  @type key :: String.t()
  @type source :: {:file, Path.t()} | {:redirect, String.t()}

  @typedoc """
  Serving hints for `fetch/2` — remote adapters bake them into the presigned
  URL (`response-content-disposition` / `-type`); the local adapter ignores
  them because the controller sets the headers itself.

    * `:disposition` — `{"attachment", filename}` or `"inline"`
    * `:content_type` — the content type the response should carry
  """
  @type fetch_opts :: [
          disposition: {String.t(), String.t()} | String.t(),
          content_type: String.t()
        ]

  @typedoc """
  Object metadata for `put/3` — remote adapters store it with the object so
  presigned GETs serve the right headers; the local adapter ignores it.
  """
  @type put_opts :: [disposition: {String.t(), String.t()} | String.t(), content_type: String.t()]

  @callback put(key, src_path :: Path.t(), put_opts) :: :ok | {:error, term()}
  @callback fetch(key, fetch_opts) :: {:ok, source} | {:error, :not_found | term()}
  @callback copy(src :: key, dest :: key) :: :ok | {:error, :not_found | term()}
  @callback delete(key) :: :ok
  @callback delete_prefix(prefix :: String.t()) :: :ok

  def adapter, do: Application.get_env(:tasky, :storage_adapter, Tasky.Storage.Local)

  def put(key, src_path, opts \\ []), do: adapter().put(key, src_path, opts)
  def fetch(key, opts \\ []), do: adapter().fetch(key, opts)

  @doc """
  Copies a stored object to a second key, keeping its metadata. Used when a
  resource is duplicated (see `Tasky.Courses.duplicate_course/3`) so the copy
  owns its own bytes instead of borrowing the source's.
  """
  def copy(src, dest), do: adapter().copy(src, dest)
  def delete(key), do: adapter().delete(key)
  def delete_prefix(prefix), do: adapter().delete_prefix(prefix)
end
