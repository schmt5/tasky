defmodule Tasky.Exams.ExportDownloadToken do
  @moduledoc """
  Signs and verifies one-time tokens that authorize a single download of an
  exported ZIP file. The token's payload is the export's opaque id (resolved
  server-side to a path under the export directory — never a filesystem path)
  plus the user-facing filename for the `Content-Disposition` header.

  Tokens expire after 15 minutes, which matches the janitor's cleanup TTL.
  """

  @salt "exam-export-download"
  @max_age 15 * 60

  def sign(endpoint, export_id, filename) do
    Phoenix.Token.sign(endpoint, @salt, {export_id, filename})
  end

  def verify(endpoint, token) when is_binary(token) do
    Phoenix.Token.verify(endpoint, @salt, token, max_age: @max_age)
  end

  def verify(_, _), do: {:error, :missing}
end
