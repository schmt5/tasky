# Architecture

Tasky is a Phoenix LiveView app (PostgreSQL via `postgrex`; Neon in production)
with React/Tiptap
editor islands. Teachers author **exams** (guest access via tokens) and
**learning units/tasks** (course-enrolled students); students answer in the
browser; teachers correct, grade and export PDFs. This document describes the
system after the refactoring tracked in `docs/ROBUSTNESS_PLAN.md`.

## Context map (`lib/tasky/`)

| Module | Responsibility |
|---|---|
| `Tasky.Accounts` | Users, sessions, roles (`admin`/`teacher`/`student`). Registration auto-confirms; **email delivery is disabled** (local adapter everywhere). |
| `Tasky.Policy` | The one authorization rule: **admins manage everything, owners manage their own**. `:system` is the trusted scope for supervised background jobs — never passed from the web layer. |
| `Tasky.Exams` | Exam CRUD, lifecycle (`draft → open → running → finished → archived`, enforced), guest enrollment/submissions, grading writes. Every mutator takes a scope (or `:system`) and authorizes internally. |
| `Tasky.Tasks` | Learning units, student submissions, review flow. Same scoping rules. |
| `Tasky.Courses` / `Tasky.Classes` | Course/class membership; `Courses.enrolled?/2` gates all student task access. Trägt auch den Kurs-Katalog: `courses.catalog_published_at` ist dort das Lese-Credential (wie `share_slug` beim KI-Link) und `import_catalog_course_records/3` der einzige Pfad, auf dem eine Lehrperson Inhalte einer anderen kopieren darf. |
| `Tasky.Feedback` | Anonymer Feedback-Briefkasten pro Kurs (`Course.feedback_box_enabled`, startet geschlossen). Die `student_id` wird gespeichert — sie trägt die Missbrauchsbremse — aber `list_messages/2` selektiert sie nicht, die Web-Schicht bekommt sie also nie zu sehen. Pseudonym, nicht absolut anonym: Texte gegenüber Lernenden sagen "die Lehrperson sieht deinen Namen nicht". |
| `Tasky.ExamDoc` | Pure Tiptap document algebra: split into parts, preamble, reassembly, answer-block labels, **stable part ids**. |
| `Tasky.Grading` | Pure grading domain: quarter-point rounding, verdict semantics, part/total computation, the **one** Swiss mark formula (screen and PDF). |
| `Tasky.Correction.AnswerKey` | Splits an answer-filled doc into answer-free `content` + an answers map keyed by `answerId`; merges them back. |
| `Tasky.Correction.StringComparator` | Deterministic auto-correction of one part (no AI; an AI client can be swapped in behind the same contract). |
| `Tasky.AI.NodePatcher` | Lists answer blocks of a doc, applies/rewrites ✅/🟡/❌ markers. |
| `Tasky.AI.BulkCorrectionRunner` | Auto-corrects all eligible (submission, part) pairs of an exam. **Singleton per exam** (Registry); overlapping triggers queue a re-run; the terminal `:bulk_correction_done` broadcast is crash-safe. |
| `Tasky.AI.CorrectionOrchestrator` | Subscribes to `"exam_events"` and starts runner jobs — the only link between `Exams` and the runner (no cycle). |
| `Tasky.Uploads` | Validation + key building for stored files (type whitelists, size caps, magic-byte sniffing for images). Physical IO goes through `Tasky.Storage`. |
| `Tasky.Storage` (+ `Local`, `R2`) | Storage behaviour (`put/fetch/delete/delete_prefix`). `Local` serves files from `UPLOADS_DIR` (dev/test); `R2` keeps a private bucket and serves via presigned URLs (prod). Selected by `STORAGE_ADAPTER` at boot. |
| `Tasky.Exams.ExportRunner` / `ExportJanitor` | PDF export via Gotenberg (serialized, retried), ZIP with failure manifest on partial success, id-signed download tokens, janitor-based tmp cleanup. |
| `Tasky.PDF.Gotenberg` | Thin Req client for the Gotenberg service (transient-error retries). |

## Document & grading model

The exam document is **Tiptap JSON**, stored as-is and rendered client-side
everywhere (editors, read-only viewers, the PDF print view) — there is no
server-side JSON→HTML rendering.

- **Answer ids**: every answer-bearing node (`answerBlock`, `lueckentext`,
  `taskItem`) carries a stable `attrs.answerId` (client-generated
  `crypto.randomUUID()`, server fallback in `AnswerKey.ensure_ids/1`). Paste
  deduplication regenerates colliding ids.
- **Part ids**: every question heading (h3) carries a stable `attrs.partId`
  (client-stamped, server fallback in `ExamDoc.ensure_part_ids/1`). All
  part-keyed data (sample-solution points, AI config, corrected parts,
  points per part) uses these ids, so reordering questions re-keys nothing.
- **Verdicts** live in `exam_submissions.block_verdicts`, keyed by the
  block's `answerId`: `"correct"`, `"wrong"`, legacy `"half"`, or a number
  (manual points, clamped/quarter-rounded). The ✅/🟡/❌ markers inside
  `corrected_content` are still written server-side on verdict changes and
  read back as an inference fallback for AI-corrected parts (making them
  fully render-only is the one open Phase-3 item, 3.3).
- **Grading writes are transactional and row-locked**: every read-modify-write
  over the JSON columns runs in a transaction that first takes a row lock via
  `Repo.lock_one!/3`; bulk operations (grouped verdicts, mark-all) are single
  transactions locking every row they touch. Submit gates re-check inside the
  transaction (TOCTOU). A plain `Repo.get!` inside a transaction is **not**
  enough under Postgres' READ COMMITTED: it sees the latest committed snapshot,
  so a concurrent writer can still commit between the check and the write.

### Lock rules

Getting these wrong produces deadlocks rather than a visible bug, so they are
binding:

1. **Table order**: `exams` → `exam_submissions` → `exam_submission_files`, and
   `tasks` → `task_submissions` → `task_submission_files`. Never lock a parent
   after a child.
2. **Within one table**: lock in ascending `id`. The bulk helpers in
   `Tasky.Exams` order by `id` (not `inserted_at`, which is not unique) so
   `LockRows` sits above `Sort` and two overlapping bulk operations cannot
   deadlock.
3. **Mode**: rows that get written take `FOR UPDATE`; rows read only as a guard
   take `FOR SHARE`. This matters for `exams`: `FOR UPDATE` conflicts with the
   `FOR KEY SHARE` that an `INSERT INTO exam_submissions` takes on the parent
   row, so it would block guest enrollment during a teacher's bulk correction.
   `FOR SHARE` does not, while still excluding `update_exam_status/3`.
4. **A row lock does not pin child rows.** The upload gates
   (`missing_required_uploads/1`) read the `*_submission_files` and
   `*_upload_fields` tables, which no lock on the submission covers. The file
   mutation paths therefore lock the parent submission row too, which is what
   makes them mutually exclusive with the submit/complete gate. Known remaining
   race, deliberately not locked: a teacher adding a required upload field while
   an exam is running.
5. A deadlock surfaces as a **raised** `Postgrex.Error` (`40P01`), not an
   `{:error, _}` return.

## Web layer (`lib/tasky_web/`)

- **No raw `Repo` under `lib/tasky_web/`** — a credo `ForbiddenModule` check
  enforces it; contexts expose accessors instead.
- Pipelines: `:browser` carries a strict CSP (`script-src 'self'`, no inline
  scripts — even the Gotenberg print-ready signal lives in the bundle);
  `/uploads` responses are sandboxed (`default-src 'none'`, nosniff, CORP);
  the guest enrollment routes are rate-limited per IP
  (`TaskyWeb.Plugs.RateLimit`; the 128-bit `exam_token` API routes are not).
- JSON APIs (autosave, images) share `TaskyWeb.ApiHelpers`
  (`render_save_result/2`, uniform errors). File downloads share
  `TaskyWeb.StorageServing` (local `send_file`/`send_download` vs. presigned
  302).
- Client params are parsed via `TaskyWeb.Params.int/1` and explicit atom
  whitelists — malformed input never crashes a LiveView.

## Frontend (`assets/js/`)

- One React/Tiptap component (`react/ExamContentEditor.jsx`) drives all
  editor modes (author, sample solution, student, correction, read-only) via
  props. Splitting it into typed TS modules is the open Phase-4.6 item.
- All React islands are built by `hooks/create_react_hook.jsx`: dynamic
  imports, destroyed-after-await guard, **loud failure** on corrupt
  `data-content` (refuses to mount so an autosave can't overwrite the server
  copy), optional lazy mounting, shared submit-flush handshake.
- Autosave (`react/api.js` + the editor's flush loop): retries transient
  failures with backoff; 401/403/login-redirects are **permanent** ("bitte
  Seite neu laden"); unload-time flushes use `keepalive`; `beforeunload`
  warns while unsaved.

## Background work

No job queue (decided): supervised in-process Tasks. A job lost to a restart
is re-triggered by the teacher. Bulk correction is a per-exam singleton; PDF
exports deliver partial results with a `FEHLER.txt` manifest; tmp ZIPs are
cleaned by `ExportJanitor`.

## Deployment

Fly.io app `learningline` (`fly.toml`, `MIX_ENV=demo`). **Stateless
machines**: the database is Neon Postgres (`DATABASE_URL`, TLS verified against
the OS CA store) and uploads are in a private R2 bucket
(`STORAGE_ADAPTER=r2`) — there is no Fly volume. Backups and PITR are Neon's.
Migrations run on boot via the `Ecto.Migrator` child in `Tasky.Application`;
`rel/overlays/bin/migrate` is the manual fallback.

`PHX_HOST` and `DATABASE_URL` are mandatory (boot fails without them), as are
the `R2_*` credentials when `STORAGE_ADAPTER=r2`. With the `local` storage
adapter, `UPLOADS_DIR` must be set explicitly in prod — there is no volume left
to derive it from.

PDF export needs `GOTENBERG_URL` and `GOTENBERG_CALLBACK_URL` (Gotenberg's
Chrome fetches token-authenticated `/print` pages back from the app and polls
`window.printReady`, which the page gates on viewer render + image load).

## Testing & CI

`mix precommit` = compile with warnings-as-errors, format check, credo
(strict), sobelow, tests — identical to CI (`.github/workflows/ci.yml`,
plus dialyzer and the asset build). Domain logic (`Grading`, `ExamDoc`,
block points, authorization rules) is unit-tested; broad LiveView/controller
coverage is the open Phase-8.1 item.
