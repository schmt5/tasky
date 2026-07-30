defmodule Tasky.Storage.R2 do
  @moduledoc """
  Cloudflare R2 storage adapter (S3-compatible, via `ReqS3`). The bucket is
  private; objects are served through short-lived presigned GET URLs the
  controllers 302-redirect to (see `TaskyWeb.StorageServing`).

  Object metadata (content type / disposition) is stored at upload time, so
  presigned GETs serve the right headers without per-request signing options.

  Config (validated at boot in `config/runtime.exs` when
  `STORAGE_ADAPTER=r2`):

      config :tasky, Tasky.Storage.R2,
        account_id: ..., bucket: ..., access_key_id: ..., secret_access_key: ...
  """

  @behaviour Tasky.Storage

  require Logger

  # Comfortably longer than a serialized multi-submission PDF export takes
  # per render, and short enough that leaked links go stale quickly.
  @presign_ttl_seconds 15 * 60

  @impl true
  def put(key, src_path, opts) do
    headers = put_headers(opts)

    case Req.put(req(), url: object_url(key), body: File.read!(src_path), headers: headers) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:r2_http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def fetch(key, _opts) do
    # Existence check first: a dangling presigned redirect would surface as a
    # raw R2 XML error instead of the app's 404 page.
    case Req.head(req(), url: object_url(key)) do
      {:ok, %Req.Response{status: 200}} -> {:ok, {:redirect, presign(key)}}
      {:ok, %Req.Response{status: 404}} -> {:error, :not_found}
      {:ok, %Req.Response{status: status}} -> {:error, {:r2_http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete(key) do
    case Req.delete(req(), url: object_url(key)) do
      {:ok, %Req.Response{status: status}} when status in [200, 204, 404] ->
        :ok

      other ->
        Logger.warning("R2 delete failed for #{key}: #{inspect(other)}")
        :ok
    end
  end

  @impl true
  def delete_prefix(prefix) do
    prefix
    |> list_keys()
    |> Enum.each(&delete/1)
  end

  defp list_keys(prefix, continuation_token \\ nil) do
    params =
      %{"prefix" => prefix <> "/", "list-type" => "2"}
      |> then(
        &if continuation_token,
          do: Map.put(&1, "continuation-token", continuation_token),
          else: &1
      )

    query = URI.encode_query(params)

    case Req.get(req(), url: "s3://#{bucket()}?#{query}") do
      {:ok, %Req.Response{status: 200, body: body}} ->
        result = body["ListBucketResult"] || %{}
        keys = result |> Map.get("Contents", []) |> List.wrap() |> Enum.map(& &1["Key"])

        case {result["IsTruncated"], result["NextContinuationToken"]} do
          {"true", token} when is_binary(token) -> keys ++ list_keys(prefix, token)
          _ -> keys
        end

      other ->
        Logger.warning("R2 list failed for #{prefix}: #{inspect(other)}")
        []
    end
  end

  defp presign(key) do
    ReqS3.presign_url(
      access_key_id: config()[:access_key_id],
      secret_access_key: config()[:secret_access_key],
      bucket: bucket(),
      key: key,
      endpoint_url: endpoint_url(),
      expires: @presign_ttl_seconds
    )
  end

  defp put_headers(opts) do
    Enum.flat_map(opts, fn
      {:content_type, type} when is_binary(type) ->
        [{"content-type", type}]

      {:disposition, {kind, filename}} ->
        [{"content-disposition", ~s(#{kind}; filename="#{sanitize_filename(filename)}")}]

      {:disposition, kind} when is_binary(kind) ->
        [{"content-disposition", kind}]

      _ ->
        []
    end)
  end

  # Header values must stay ASCII/quote-safe; the exact original name is
  # still preserved in the DB and in the app-served download path.
  defp sanitize_filename(name) do
    name
    |> String.replace(~s("), "'")
    |> String.to_charlist()
    |> Enum.map(fn c -> if c in 32..126, do: c, else: ?_ end)
    |> List.to_string()
  end

  defp object_url(key), do: "s3://#{bucket()}/#{key}"

  defp req do
    Req.new(retry: :transient, max_retries: 2)
    |> ReqS3.attach(
      aws_sigv4: [
        access_key_id: config()[:access_key_id],
        secret_access_key: config()[:secret_access_key],
        endpoint_url: endpoint_url()
      ]
    )
  end

  defp endpoint_url, do: "https://#{config()[:account_id]}.r2.cloudflarestorage.com"
  defp bucket, do: config()[:bucket]
  defp config, do: Application.fetch_env!(:tasky, __MODULE__)
end
