# Tasky

A learning platform for schools: teachers author tasks and exams with a rich-text
(Tiptap) editor, students and guests work on them in the browser, and teachers
correct, grade, and export the results as PDFs.

Built with Phoenix LiveView and SQLite. The content editors are React/Tiptap
islands mounted via LiveView hooks; exam documents are stored as Tiptap JSON and
rendered client-side everywhere, including for PDF export (via Gotenberg).

## Getting started

Requirements: Elixir ~> 1.18 / OTP 28, Node.js 22.

```sh
mix setup        # deps, database, assets (incl. npm install)
mix phx.server   # http://localhost:4000
```

Seeds create initial users — see `priv/repo/seeds.exs`.

## Development

```sh
mix precommit    # compile --warnings-as-errors, format, credo --strict, sobelow, tests
mix test         # test suite only
mix coveralls    # tests with coverage report
mix dialyzer     # type analysis (first run builds the PLT, takes a while)
```

CI (GitHub Actions, `.github/workflows/ci.yml`) runs the same checks on every
push to `be-med`/`main` and on pull requests.

## Architecture & docs

- `ARCHITECTURE.md` — system overview
- `docs/ROBUSTNESS_PLAN.md` — the phased refactoring/hardening plan and the
  project-wide decisions (beta: no backward compatibility; storage moving to R2;
  admin sees everything)
- `docs/` — feature guides (courses, bulk correction, style guide)
- `AGENTS.md` — conventions for AI coding agents working in this repo

## Deployment

Deployed on Fly.io. The live app is `tasky-be-med` (`fly.be-med.toml`), deployed
from the `be-med` branch; `fly.toml`/`tasky-learn` is a secondary target. The
release runs with `MIX_ENV=demo` (see `config/demo.exs`) and stores the SQLite
database on a Fly volume.

```sh
fly deploy -c fly.be-med.toml
```

### File storage (R2)

Set `STORAGE_ADAPTER=r2` plus `R2_ACCOUNT_ID`, `R2_BUCKET`, `R2_ACCESS_KEY_ID`
and `R2_SECRET_ACCESS_KEY` to store uploads in a **private Cloudflare R2
bucket** served via presigned URLs (the default `local` keeps files on the
volume). Credentials are validated at boot. Cutover, not migration: existing
volume files are not copied over (beta rule).

### Database backups (Litestream)

Set `LITESTREAM_ENABLED=true` plus `LITESTREAM_R2_ACCOUNT_ID`,
`LITESTREAM_R2_BUCKET` (a **separate** bucket from uploads),
`LITESTREAM_R2_ACCESS_KEY_ID` and `LITESTREAM_R2_SECRET_ACCESS_KEY` to
continuously replicate the SQLite database to R2. On boot with an empty
volume the entrypoint restores the latest replica automatically.

Manual restore (e.g. onto a fresh machine):

```sh
fly ssh console -c fly.be-med.toml
litestream restore -config /app/litestream.yml -o "$DATABASE_PATH" "$DATABASE_PATH"
```

Test the restore path once after enabling — a backup that was never restored
is not a backup.

Note: transactional email is currently **disabled** — the mailer uses the local
in-memory adapter in all environments, so no email ever leaves the app
(decision recorded in `docs/ROBUSTNESS_PLAN.md`, Phase 1). No user-facing flow
depends on delivery: registration confirms accounts immediately and email
changes in the settings are applied directly, without a confirmation mail.
