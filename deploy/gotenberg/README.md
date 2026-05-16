# Gotenberg — shared PDF rendering service

This directory contains a Fly.io deployment for [Gotenberg](https://gotenberg.dev),
a stateless API that converts HTML / URLs / Office documents to PDF.

It's deployed as a **separate Fly app** so multiple Phoenix apps in the same
Fly organization can share one Gotenberg instance.

## One-time setup

```sh
# Pick a globally-unique app name (Fly app names are unique across all of Fly).
fly apps create webbau-gotenberg

# Deploy
fly deploy -c deploy/gotenberg/fly.toml -a webbau-gotenberg
```

After deploy, Gotenberg is reachable from any Fly app in your org at:

```
http://webbau-gotenberg.internal:3000
```

The instance auto-stops when idle (`auto_stop_machines = "stop"`) so cost is
near zero between PDF jobs. First request after idle adds ~5s cold-start.

## Wiring a Phoenix app to it

Set `GOTENBERG_URL` on the consuming app:

```sh
fly secrets set GOTENBERG_URL="http://webbau-gotenberg.internal:3000" -a <your-app>
```

The app's `config/runtime.exs` reads this env var. If unset, the PDF export
feature stays disabled.

## Local development

The project root has a `docker-compose.yml` that runs Gotenberg on
`http://localhost:3000`:

```sh
docker compose up gotenberg -d
```

Local Phoenix dev defaults to `http://localhost:3000` for `GOTENBERG_URL`.

## Updating Gotenberg

```sh
# Bump image version in fly.toml, then:
fly deploy -c deploy/gotenberg/fly.toml -a webbau-gotenberg
```
