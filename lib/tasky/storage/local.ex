defmodule Tasky.Storage.Local do
  @moduledoc """
  Local-filesystem storage adapter: files live under the configured
  `:uploads_dir` and are served with `send_file`.
  """

  @behaviour Tasky.Storage

  @impl true
  def put(key, src_path, _opts) do
    dest = Path.join(root(), key)
    File.mkdir_p!(Path.dirname(dest))
    File.cp!(src_path, dest)
    :ok
  end

  @impl true
  def fetch(key, _opts) do
    path = Path.join(root(), key)
    if File.regular?(path), do: {:ok, {:file, path}}, else: {:error, :not_found}
  end

  @impl true
  def copy(src, dest) do
    src_path = Path.join(root(), src)

    if File.regular?(src_path) do
      dest_path = Path.join(root(), dest)
      File.mkdir_p!(Path.dirname(dest_path))

      case File.cp(src_path, dest_path) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :not_found}
    end
  end

  @impl true
  def delete(key) do
    _ = File.rm(Path.join(root(), key))
    :ok
  end

  @impl true
  def delete_prefix(prefix) do
    _ = File.rm_rf(Path.join(root(), prefix))
    :ok
  end

  defp root, do: Application.fetch_env!(:tasky, :uploads_dir)
end
