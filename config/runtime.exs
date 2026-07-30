import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/tasky start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :tasky, TaskyWeb.Endpoint, server: true
end

config :tasky, TaskyWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Gotenberg PDF rendering service. When unset, the PDF export feature is
# disabled at runtime. Local dev defaults to the docker-compose service on
# localhost:3000.
config :tasky,
  gotenberg_url:
    System.get_env("GOTENBERG_URL") ||
      if(config_env() == :dev, do: "http://localhost:3000", else: nil)

# Base URL Gotenberg uses to fetch print-view pages back from Phoenix.
# In dev, Gotenberg runs in Docker and reaches the host via host.docker.internal.
# In prod on Fly.io, set this to the app's `.internal` DNS, e.g.
#   GOTENBERG_CALLBACK_URL=http://tasky.internal:8080
config :tasky,
  gotenberg_callback_url:
    System.get_env("GOTENBERG_CALLBACK_URL") ||
      if(config_env() == :dev, do: "http://host.docker.internal:4000", else: nil)

# Directory where uploaded exam images are stored and served from (/uploads).
# Must NOT live under priv/static — Plug.Static serves that dir and (in dev,
# with raise_on_missing_only) would raise on files it doesn't whitelist. The
# UploadController is the single serving path in all envs. Dev writes into
# priv/uploads; test into a tmp dir; prod uses R2 and never reads this.
config :tasky,
  uploads_dir:
    System.get_env("UPLOADS_DIR") ||
      (case config_env() do
         :test -> Path.join(System.tmp_dir!(), "tasky_test_uploads")
         _ -> Path.expand("priv/uploads")
       end)

# File storage: "local" (default — files on disk under UPLOADS_DIR) or
# "r2" (private Cloudflare R2 bucket served via presigned URLs; see
# docs/ROBUSTNESS_PLAN.md Phase 6). R2 credentials are validated here at
# boot so a misconfigured deployment fails fast instead of 500ing on the
# first upload.
case System.get_env("STORAGE_ADAPTER", "local") do
  "local" ->
    config :tasky, storage_adapter: Tasky.Storage.Local

  "r2" ->
    config :tasky, storage_adapter: Tasky.Storage.R2

    config :tasky, Tasky.Storage.R2,
      account_id: System.fetch_env!("R2_ACCOUNT_ID"),
      bucket: System.fetch_env!("R2_BUCKET"),
      access_key_id: System.fetch_env!("R2_ACCESS_KEY_ID"),
      secret_access_key: System.fetch_env!("R2_SECRET_ACCESS_KEY")

  other ->
    raise "STORAGE_ADAPTER must be \"local\" or \"r2\", got: #{inspect(other)}"
end

if config_env() in [:prod, :demo] do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: postgres://user:pass@ep-xxx.eu-central-1.aws.neon.tech/neondb
      """

  # The `:ssl` option is what actually enables TLS — an `?sslmode=require` in
  # DATABASE_URL is merged into the repo options and then ignored by Postgrex,
  # so do not drop this because the URL "already says require". Neon requires
  # TLS; `cacerts_get/0` verifies against the OS certificate store, which is why
  # the runtime image installs ca-certificates.
  config :tasky, Tasky.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    ssl: [cacerts: :public_key.cacerts_get()],
    socket_options: if(System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: [])

  # Uploads belong in R2 (STORAGE_ADAPTER=r2). With the local adapter there is
  # no longer a persistent volume to derive a path from, so UPLOADS_DIR has to
  # be explicit — the dev/test default above would otherwise put files inside
  # the release directory, where they vanish on the next deploy.
  if System.get_env("STORAGE_ADAPTER", "local") == "local" do
    config :tasky,
      uploads_dir:
        System.get_env("UPLOADS_DIR") ||
          raise("""
          environment variable UPLOADS_DIR is missing.
          It is required when STORAGE_ADAPTER=local (the default): point it at a
          persistent path, or set STORAGE_ADAPTER=r2 to store uploads in R2.
          """)
  end

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host =
    System.get_env("PHX_HOST") ||
      raise """
      environment variable PHX_HOST is missing.
      Set it to the public hostname of this deployment (e.g. learningline.fly.dev) —
      URLs in the app would otherwise silently point at a wrong host.
      """

  config :tasky, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :tasky, TaskyWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :tasky, TaskyWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :tasky, TaskyWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :tasky, Tasky.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
