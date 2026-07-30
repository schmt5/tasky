# Tasky

A learning platform for schools: teachers author tasks and exams with a rich-text
(Tiptap) editor, students and guests work on them in the browser, and teachers
correct, grade, and export the results as PDFs.

Built with Phoenix LiveView and PostgreSQL. The content editors are React/Tiptap
islands mounted via LiveView hooks; exam documents are stored as Tiptap JSON and
rendered client-side everywhere, including for PDF export (via Gotenberg).

## Getting started

Requirements: Elixir ~> 1.18 / OTP 28, Node.js 22, PostgreSQL 18.

The dev and test configs expect Postgres on **port 5433** with trust auth for
your OS user (a Homebrew `postgresql@18` cluster kept off the default port, so
it can coexist with other local clusters). Override with the usual
`PGHOST`/`PGPORT`/`PGUSER`/`PGPASSWORD` if your setup differs.

```sh
brew install postgresql@18
echo "port = 5433" >> "$(brew --prefix)/var/postgresql@18/postgresql.conf"
brew services start postgresql@18
```

```sh
mix setup        # deps, database, assets (incl. npm install)
mix phx.server   # http://localhost:4000
```

For demo data (a teacher, students, an exam with submissions):

```sh
mix run priv/repo/demo_submissions.exs
```

## Development

```sh
mix precommit    # compile --warnings-as-errors, format, credo --strict, sobelow, tests
mix test         # test suite only
mix coveralls    # tests with coverage report
mix dialyzer     # type analysis (first run builds the PLT, takes a while)
```

CI (GitHub Actions, `.github/workflows/ci.yml`) runs the same checks on every
push to `main` and on pull requests.

## Architecture & docs

- `ARCHITECTURE.md` — system overview
- `docs/ROBUSTNESS_PLAN.md` — the phased refactoring/hardening plan and the
  project-wide decisions (beta: no backward compatibility; storage moving to R2;
  admin sees everything)
- `docs/` — feature guides (courses, bulk correction, style guide)
- `AGENTS.md` — conventions for AI coding agents working in this repo

## Deployment

Deployed on Fly.io as **`learningline`** (`fly.toml`, region `fra` to match the
Neon project's `eu-central-1`). The release runs with `MIX_ENV=demo` (see
`config/demo.exs`). The machines are stateless: the database is **Neon**
Postgres and uploads live in **R2**, so there is no Fly volume. Migrations run
automatically on boot via the `Ecto.Migrator` child in `Tasky.Application`.

```sh
fly deploy
```

First-time setup for a fresh app:

```sh
fly apps create learningline
fly secrets set \
  DATABASE_URL='postgres://neondb_owner:<password>@ep-polished-sunset-a2gyeh2t.eu-central-1.aws.neon.tech/neondb' \
  SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  R2_ACCOUNT_ID=... R2_BUCKET=... R2_ACCESS_KEY_ID=... R2_SECRET_ACCESS_KEY=...
fly deploy
```

Boot fails fast with a named error if any of `DATABASE_URL`, `SECRET_KEY_BASE`,
`PHX_HOST` or the `R2_*` credentials is missing — a misconfigured deploy never
reaches the first request.

### Database (Neon)

`DATABASE_URL` points at the Neon project's **direct** (unpooled) endpoint —
not the `-pooler` host: Ecto already pools connections, and PgBouncer's
transaction mode would additionally require `prepare: :unnamed`. TLS is
mandatory and is verified against the OS certificate store, so the runtime
image must keep `ca-certificates` installed.

Backups and point-in-time restore are Neon's (dashboard → Backup & restore);
there is nothing to run in the app.

### File storage (R2)

`STORAGE_ADAPTER=r2` plus `R2_ACCOUNT_ID`, `R2_BUCKET`, `R2_ACCESS_KEY_ID` and
`R2_SECRET_ACCESS_KEY` stores uploads in a **private Cloudflare R2 bucket**
served via short-lived presigned URLs. Credentials are validated at boot. Keep
the bucket private — the adapter's whole design is the expiring redirect, and a
public `r2.dev` URL would turn every upload link into a permanent one.

The `local` adapter (dev/test default) keeps files on disk under `UPLOADS_DIR`;
in prod it requires `UPLOADS_DIR` to be set explicitly, since there is no volume
to derive a path from.

Note: transactional email is currently **disabled** — the mailer uses the local
in-memory adapter in all environments, so no email ever leaves the app
(decision recorded in `docs/ROBUSTNESS_PLAN.md`, Phase 1). No user-facing flow
depends on delivery: registration confirms accounts immediately and email
changes in the settings are applied directly, without a confirmation mail.
