defmodule Tasky.Exams.ExportJanitor do
  @moduledoc """
  Deletes stale export ZIPs from `Tasky.Exams.ExportRunner.export_dir/0`.

  Runs a sweep at startup (files left behind by a previous instance — a
  sleeping cleanup task dies with its node) and then periodically. Files
  older than the TTL are removed; the TTL comfortably exceeds the download
  token's 15-minute validity.
  """

  use GenServer

  require Logger

  alias Tasky.Exams.ExportRunner

  @sweep_interval_ms 10 * 60 * 1000
  @ttl_seconds 20 * 60

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{}, {:continue, :sweep}}
  end

  @impl true
  def handle_continue(:sweep, state) do
    sweep()
    Process.send_after(self(), :sweep, @sweep_interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    {:noreply, state, {:continue, :sweep}}
  end

  defp sweep do
    dir = ExportRunner.export_dir()
    cutoff = System.system_time(:second) - @ttl_seconds

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&(Path.extname(&1) == ".zip"))
        |> Enum.each(&remove_if_stale(Path.join(dir, &1), cutoff))

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        Logger.warning("Export janitor could not list #{dir}: #{inspect(reason)}")
    end

    :ok
  end

  defp remove_if_stale(path, cutoff) do
    with {:ok, %File.Stat{mtime: mtime}} <- File.stat(path, time: :posix),
         true <- mtime < cutoff do
      _ = File.rm(path)
    end

    :ok
  end
end
