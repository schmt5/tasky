defmodule Tasky.Exams.ExportDownloadToken do
  @moduledoc """
  Signs and verifies one-time tokens that authorize a single download of an
  exported ZIP file. The token's payload is the absolute file path plus the
  user-facing filename for the `Content-Disposition` header.

  Tokens expire after 15 minutes, which matches the cleanup fallback in
  `Tasky.Exams.ExportRunner`.
  """

  @salt "exam-export-download"
  @max_age 15 * 60

  def sign(endpoint, path, filename) do
    Phoenix.Token.sign(endpoint, @salt, {path, filename})
  end

  def verify(endpoint, token) when is_binary(token) do
    Phoenix.Token.verify(endpoint, @salt, token, max_age: @max_age)
  end

  def verify(_, _), do: {:error, :missing}
end
