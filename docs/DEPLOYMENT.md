# Deployment

LearningLine runs on [Fly.io](https://fly.io) as the app **`learningline`**
(`fly.toml`, region `fra` to match the Neon project's `eu-central-1`). The
release runs with `MIX_ENV=demo` (see `config/demo.exs`).

The machines are stateless: the database is **Neon** Postgres and uploads live
in **Cloudflare R2**, so there is no Fly volume. Migrations run automatically
on boot via the `Ecto.Migrator` child in `Tasky.Application`.

```sh
fly deploy
```

## First-time setup

```sh
fly apps create learningline
fly secrets set \
  DATABASE_URL='postgres://<user>:<password>@<neon-endpoint>.eu-central-1.aws.neon.tech/<db>' \
  SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  R2_ACCOUNT_ID=... R2_BUCKET=... R2_ACCESS_KEY_ID=... R2_SECRET_ACCESS_KEY=...
fly deploy
```

Boot fails fast with a named error if any of `DATABASE_URL`, `SECRET_KEY_BASE`,
`PHX_HOST` or the `R2_*` credentials is missing — a misconfigured deploy never
reaches the first request.

## Database (Neon)

`DATABASE_URL` points at the Neon project's **direct** (unpooled) endpoint —
not the `-pooler` host: Ecto already pools connections, and PgBouncer's
transaction mode would additionally require `prepare: :unnamed`. TLS is
mandatory and is verified against the OS certificate store, so the runtime
image must keep `ca-certificates` installed.

Backups and point-in-time restore are Neon's (dashboard → Backup & restore);
there is nothing to run in the app.

## File storage (R2)

`STORAGE_ADAPTER=r2` plus `R2_ACCOUNT_ID`, `R2_BUCKET`, `R2_ACCESS_KEY_ID` and
`R2_SECRET_ACCESS_KEY` stores uploads in a **private Cloudflare R2 bucket**
served via short-lived presigned URLs. Credentials are validated at boot. Keep
the bucket private — the adapter's whole design is the expiring redirect, and a
public `r2.dev` URL would turn every upload link into a permanent one.

The `local` adapter (dev/test default) keeps files on disk under `UPLOADS_DIR`;
in prod it requires `UPLOADS_DIR` to be set explicitly, since there is no volume
to derive a path from.

## Email

Transactional email is currently **disabled** — the mailer uses the local
in-memory adapter in all environments, so no email ever leaves the app
(decision recorded in `docs/ROBUSTNESS_PLAN.md`, Phase 1). No user-facing flow
depends on delivery: registration confirms accounts immediately and email
changes in the settings are applied directly, without a confirmation mail.
