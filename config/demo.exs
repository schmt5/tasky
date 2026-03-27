import Config

# Like prod: serve digested static files from cache manifest
config :tasky, TaskyWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"

# Like prod: force SSL
config :tasky, TaskyWeb.Endpoint,
  force_ssl: [rewrite_on: [:x_forwarded_proto]],
  exclude: [
    hosts: ["localhost", "127.0.0.1"]
  ]

# Use local adapter so emails are stored in-memory and visible at /dev/mailbox
config :tasky, Tasky.Mailer, adapter: Swoosh.Adapters.Local

# Use the Req-based API client for any other Swoosh adapters that may be used
config :swoosh, api_client: Swoosh.ApiClient.Req

# Do not print debug messages in demo
config :logger, level: :info
