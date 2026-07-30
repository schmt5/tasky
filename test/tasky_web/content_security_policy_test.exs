defmodule TaskyWeb.ContentSecurityPolicyTest do
  use ExUnit.Case, async: false

  alias TaskyWeb.ContentSecurityPolicy

  setup do
    previous = Application.get_env(:tasky, :storage_adapter)
    on_exit(fn -> Application.put_env(:tasky, :storage_adapter, previous) end)
    :ok
  end

  defp img_src(policy) do
    policy
    |> String.split("; ")
    |> Enum.find(&String.starts_with?(&1, "img-src "))
  end

  test "keeps uploads on 'self' with the local adapter" do
    Application.put_env(:tasky, :storage_adapter, Tasky.Storage.Local)

    assert img_src(ContentSecurityPolicy.page()) == "img-src 'self' data: blob:"
  end

  # /uploads answers with a 302 onto the R2 endpoint and CSP re-checks the
  # redirect target — without the origin here every content image is blocked
  # while the app still logs a healthy 302.
  test "allows the R2 endpoint with the remote adapter" do
    Application.put_env(:tasky, :storage_adapter, Tasky.Storage.R2)

    Application.put_env(:tasky, Tasky.Storage.R2,
      account_id: "acct123",
      bucket: "bucket",
      access_key_id: "key",
      secret_access_key: "secret"
    )

    assert img_src(ContentSecurityPolicy.page()) ==
             "img-src 'self' data: blob: https://acct123.r2.cloudflarestorage.com"
  end

  test "carries the non-storage directives unchanged" do
    policy = ContentSecurityPolicy.page()

    for directive <- [
          "default-src 'self'",
          "script-src 'self'",
          "style-src 'self' 'unsafe-inline'",
          "object-src 'none'",
          "frame-ancestors 'self'",
          "form-action 'self'"
        ] do
      assert directive in String.split(policy, "; ")
    end
  end
end
