defmodule Tasky.ProbeStorage do
  @moduledoc """
  Test storage adapter that reports every `copy/2` back to an owner process
  and then delegates to `Tasky.Storage.Local`.

  It exists to assert the one invariant that is invisible from the outside:
  no storage I/O may happen inside the duplication's `Repo.transaction/1`
  (see `Tasky.Courses.duplicate_course/3`). Each call sends

      {:storage_copy, src, dest, in_transaction?}

  so a test can `refute_receive` across the record phase, and it can be
  switched to fail or raise to exercise the partial-failure paths.
  """

  @behaviour Tasky.Storage

  @doc """
  Installs the adapter for the current test and restores the previous one on
  exit. `copy_result` and `delete_prefix_result` are `:delegate` (default),
  `{:error, reason}` or `:raise`.
  """
  def install(opts \\ []) do
    previous = Application.get_env(:tasky, :storage_adapter)

    Application.put_env(:tasky, :probe_storage, %{
      owner: Keyword.get(opts, :owner, self()),
      copy_result: Keyword.get(opts, :copy_result, :delegate),
      delete_prefix_result: Keyword.get(opts, :delete_prefix_result, :delegate)
    })

    Application.put_env(:tasky, :storage_adapter, __MODULE__)

    ExUnit.Callbacks.on_exit(fn ->
      Application.delete_env(:tasky, :probe_storage)

      if previous,
        do: Application.put_env(:tasky, :storage_adapter, previous),
        else: Application.delete_env(:tasky, :storage_adapter)
    end)

    :ok
  end

  @impl true
  def copy(src, dest) do
    config = Application.fetch_env!(:tasky, :probe_storage)
    send(config.owner, {:storage_copy, src, dest, Tasky.Repo.in_transaction?()})

    case config.copy_result do
      :delegate -> Tasky.Storage.Local.copy(src, dest)
      :raise -> raise "probe storage: copy blew up"
      other -> other
    end
  end

  @impl true
  def put(key, src_path, opts), do: Tasky.Storage.Local.put(key, src_path, opts)

  @impl true
  def fetch(key, opts), do: Tasky.Storage.Local.fetch(key, opts)

  @impl true
  def delete(key), do: Tasky.Storage.Local.delete(key)

  @impl true
  def delete_prefix(prefix) do
    config = Application.fetch_env!(:tasky, :probe_storage)
    send(config.owner, {:storage_delete_prefix, prefix, Tasky.Repo.in_transaction?()})

    case config.delete_prefix_result do
      :delegate -> Tasky.Storage.Local.delete_prefix(prefix)
      :raise -> raise "probe storage: delete_prefix blew up"
      other -> other
    end
  end
end
