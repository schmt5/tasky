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
| `Tasky.Accounts` | Users, sessions, roles (`admin`/`teacher`/`student`). Registration auto-confirms; **email delivery is disabled** (local adapter everywhere). **There is no open registration**: `register_user/2` takes an invitation — `{:class, class}` from `?class=<slug>` makes a student, `{:organization, org}` from `?invite=<token>` makes a teacher. `role`, `class_id` and `organization_id` are **not castable**, so registering into a foreign organization is structurally impossible rather than validated. |
| `Tasky.Policy` | Two orthogonal rules. **Ownership** for courses/units/exams: admins manage everything, owners manage their own; colleagues do *not* see each other's. **Organization** for classes and students: teachers of one organization share its classes and every student in them (`organization_scope/1`, `scope_by_organization/3`). Fail-closed — no organization means no visibility, because the columns shipped without a backfill and NULL is the normal state right after deploy. `:system` is the trusted scope for supervised background jobs — never passed from the web layer. |
| `Tasky.Organizations` | The tenant boundary. **Teachers carry the organization themselves** (`users.organization_id`); **students derive theirs from their class** (`classes.organization_id` via `users.class_id`) — never write `users.organization_id` for a student, a check constraint enforces it. `organizations.invite_token` is the most valuable credential in the app: it turns a visitor into a *teacher* with full sight of the organization, hence a random token rather than the guessable `slug`, and hence `rotate_invite_token/2`. Administration is admin-only; the token lookup is deliberately unauthenticated. |
| `Tasky.Exams` | Exam CRUD, lifecycle (`draft → open → running → finished → archived`, enforced), guest enrollment/submissions, grading writes. Every mutator takes a scope (or `:system`) and authorizes internally. |
| `Tasky.Tasks` | Learning units, student submissions, review flow. Same scoping rules. |
| `Tasky.Courses` / `Tasky.Classes` | Course/class membership; `Courses.enrolled?/2` gates all student task access. A class belongs to one organization and is shared by its teachers; `Tasky.Classes` is the **only** context that threads a `%Scope{}` for this, because classes have no owner. Everywhere else **the organization comes from the owner of the resource, not from the caller's scope** — a course carries `teacher_id` and the teacher carries the organization, which keeps the signatures unchanged and makes the rule hold even when an admin acts. Resist re-introducing scope parameters. The **catalog stays global on purpose**: it is the cross-organization exchange, so a course author's name is visible across organizations. Trägt auch den Kurs-Katalog: `courses.catalog_published_at` ist dort das Lese-Credential (wie `share_slug` beim KI-Link) und `import_catalog_course_records/3` der einzige Pfad, auf dem eine Lehrperson Inhalte einer anderen kopieren darf. |
| `Tasky.Feedback` | Anonymer Feedback-Briefkasten pro Kurs (`Course.feedback_box_enabled`, startet geschlossen). Die `student_id` wird gespeichert — sie trägt die Missbrauchsbremse — aber `list_messages/2` selektiert sie nicht, die Web-Schicht bekommt sie also nie zu sehen. Pseudonym, nicht absolut anonym: Texte gegenüber Lernenden sagen "die Lehrperson sieht deinen Namen nicht". |
| `Tasky.ExamDoc` | Pure Tiptap document algebra: split into parts, preamble, reassembly, answer-block labels, **stable part ids**. Mode-aware: `split_content_into_parts/2` takes the exam's `answer_mode`. |
| `Tasky.ExamPaper` | Pure paper-version algebra: the layout map (`exams.paper_layout`) ↔ the printable document. Sizes each answer box to its stored line count (starting size derived from the question's points), clears the checkboxes and appends the points to each question heading. `extract_layout/1` is the inverse and the save path's guard — it reads paragraph *counts* and nothing else. |
| `Tasky.Grading` | Pure grading domain: two rounding grids (points always 0.25, marks per exam), verdict semantics, part/total computation, the **one** Swiss mark formula (screen and PDF). |
| `Tasky.Correction.AnswerKey` | Splits an answer-filled doc into answer-free `content` + an answers map keyed by `answerId`; merges them back. |
| `Tasky.Correction.StringComparator` | Deterministic auto-correction of one part (no AI; an AI client can be swapped in behind the same contract). |
| `Tasky.Correction.AnswerVariants` | Das `;` in einer Musterlösung: die eine Regel, was eine gültige Alternative ist. `split/1` für jeden Bewerter (`StringComparator`, `SelfCheck`, die Gruppen-Korrektur in `Exams`), `humanize_answer/2` und `humanize_doc/1` für die Anzeige. Das Trennzeichen ist ein **Autoren**-Format: Lernenden wird `"pdf;.pdf"` als „pdf, .pdf" vorgelegt, denn wer das `;` nicht kennt, liest es als Teil der Antwort. Anzeige und Bewertung teilen sich die Regel deshalb bewusst — liefen sie auseinander, würde eine Antwort als richtig gelten, die in der gezeigten Musterlösung gar nicht steht. Umgeschrieben wird nur für Lernende; die Editoren der Lehrperson zeigen weiter das rohe `;`. |
| `Tasky.Correction.SolutionHints` | Die Vergleichsansicht für Lernende: hängt die Musterlösung als `solutionHint` unter das Antwortfeld und das Verdikt als Attribut an den Knoten (den Marker zeichnet das Stylesheet, nicht der Text). Geteilt von der Selbstkontrolle einer Lerneinheit (`Tasky.Tasks.SelfCheck`) und der zurückgegebenen Prüfung (`Exams.return_doc_for_learner/3`) — die beiden Flächen dürfen nicht auseinanderlaufen. Gepaart wird über `answerId`. |
| `Tasky.AI.NodePatcher` | Lists answer blocks of a doc, applies/rewrites ✅/🟡/❌ markers. |
| `Tasky.AI.BulkCorrectionRunner` | Auto-corrects all eligible (submission, part) pairs of an exam. **Singleton per exam** (Registry); overlapping triggers queue a re-run; the terminal `:bulk_correction_done` broadcast survives an exception via `try/after`, but **not** a brutal kill or node shutdown — a job lost that way is re-triggered by the teacher (the "no job queue" decision). |
| `Tasky.AI.CorrectionOrchestrator` | Subscribes to `"exam_events"` and starts runner jobs — the only link between `Exams` and the runner (no cycle). |
| `Tasky.Uploads` | Validation + key building for stored files (type whitelists, size caps, magic-byte sniffing for images). Physical IO goes through `Tasky.Storage`. |
| `Tasky.Storage` (+ `Local`, `R2`) | Storage behaviour (`put/fetch/delete/delete_prefix`). `Local` serves files from `UPLOADS_DIR` (dev/test); `R2` keeps a private bucket and serves via presigned URLs (prod). Selected by `STORAGE_ADAPTER` at boot. |
| `Tasky.Exams.ExportRunner` / `ExportJanitor` | PDF export via Gotenberg (serialized, retried), ZIP with failure manifest on partial success, id-signed download tokens, janitor-based tmp cleanup. |
| `Tasky.PDF.Gotenberg` | Thin Req client for the Gotenberg service (transient-error retries). |

## Document & grading model

The exam document is **Tiptap JSON**, stored as-is and rendered client-side
everywhere (editors, read-only viewers, the PDF print view) — there is no
server-side JSON→HTML rendering.

- **The paper version never touches `content`.** How tall each answer box is
  on paper lives in its own column (`exams.paper_layout`, `%{answer_id =>
  lines}`), written only by `Exams.update_paper_layout/3`. The teacher sizes a
  box by pressing Enter in it — a box is made of empty paragraphs, so a line
  *is* a paragraph — and writing that into `content` would put blank paragraphs
  into the document the learners sit. Storing only the counts also means the
  layout survives later edits: a new answer field starts from its points, a
  stale entry is ignored. The invariant above still holds — `Tasky.ExamPaper`
  transforms document → document, never document → HTML.

- **Answer mode** (`exams.answer_mode`) picks between the two kinds of exam.
  `"answer_fields"` is the original one: questions are `h3` headings, answers
  go into `answerBlock` / `lueckentext` / `taskItem` nodes, and the learner's
  editor vetoes every edit outside those nodes. `"free_document"` has neither:
  the learner edits the teacher's document itself. It is **castable in
  `Exam.new_changeset/2` only** — chosen once on the create form and never
  again, because part ids, answer ids, verdicts and the sample solution all
  hang off it and a switch would strand them rather than convert them.
  `duplicate_exam/3` therefore has to carry it over explicitly.
- **A free document is one part.** `ExamDoc.split_content_into_parts/2`
  returns a single synthetic part (`ExamDoc.free_document_part_id/0`,
  `"document"`) spanning the whole doc, and the preamble is empty. That one
  decision is what lets `points_per_part`, `corrected_parts`,
  `sample_solution_points`, the correction editor, the mark formula and the
  PDF export work on an essay without knowing it is one. Grading happens
  through `set_part_points/4` — with no answer blocks, `resolve_block_points/3`
  is `nil`, so block verdicts write nothing. Auto-correction is short-circuited
  to `[]` and the grouped "Korrektur nach Frage" view redirects away, since
  both need answer fields to work on. The mode argument has **no default**: a
  call site that forgot it would silently report "no parts" for every essay.

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
  (manual points, quarter-rounded then clamped — in that order, because
  equal-split block maxima are not on the 0.25 grid). This vocabulary is
  binding for **every** writer including `Correction.StringComparator`; a
  verdict outside it silently loses its marker and reads as ungraded.
  The ✅/🟡/❌ markers inside `corrected_content` are still written
  server-side on verdict changes and read back as an inference fallback for
  AI-corrected parts (making them fully render-only is the one open Phase-3
  item, 3.3).
- **Two rounding grids, one formula.** Points are on the 0.25 grid for every
  exam (`Grading.round_quarter/1` and everything built on it). The **mark** is
  on `exams.mark_step` — 0.25 or 0.1, the teacher's choice, made once on the
  way into the Benotung and changeable afterwards. `nil` means "not asked
  yet": it falls back to 0.25 via `Exams.mark_step/1`, which is the only place
  that fallback exists — `Grading.round_mark/2` raises for an unknown step so a
  caller that forgets to resolve it fails loudly. `Exams.set_mark_step/3`
  re-rounds the submissions' stored manual marks in the same transaction, so
  the column and the marks can never disagree. The `submission.mark ||
  calculated` precedence lives in `Exams.grading_result/2` **only** — grading
  table, PDF export and the learner's view all call it, because this formula
  once existed twice and the PDF printed a different mark than the screen.
- **The auto-corrector never overwrites the teacher.** `auto_block_verdicts`
  records what the runner last wrote; a block whose current verdict differs
  from that is the teacher's and survives every re-run, markers included.
  This matters because a part stays eligible for auto-correction until it is
  marked corrected — so editing any model answer re-runs parts the teacher is
  midway through grading.
- **Grading writes are transactional and row-locked**: every read-modify-write
  over the JSON columns runs in a transaction that first takes a row lock via
  `Repo.lock_one!/3`; bulk operations (grouped verdicts, mark-all) are single
  transactions locking every row they touch. Submit gates re-check inside the
  transaction (TOCTOU). `Exams.set_mark_step/3` is the one writer that takes
  `FOR UPDATE` on `exams` rather than `FOR SHARE`: it writes that row *and*
  must exclude a concurrent `set_submission_mark/3`, which reads the step
  under `FOR SHARE` before writing the submission.
  A plain `Repo.get!` inside a transaction is **not**
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
- **Safe Exam Browser enforcement** is the second thing that has to cover both
  a plug and an `on_mount` hook, for the same reason the rate limiter does: the
  guest LiveViews share one `live_session`, so a `live_redirect` joins over the
  open websocket and never touches a pipeline again. The decision logic lives
  in `TaskyWeb.SebGuard`; `TaskyWeb.Plugs.SebGuard` and
  `TaskyWeb.SebGuardHook` are thin callers. A verified HTTP request stamps the
  session, and the hook accepts that stamp — SEB's headers cannot be assumed to
  survive a WebSocket upgrade. Per-exam mode (`off`/`observe`/`enforce`)
  defaults to `observe`: see `docs/SEB_PROBELAUF.md` for why nothing may be
  switched to `enforce` before a dry run against a real client.
- JSON APIs (autosave, images) share `TaskyWeb.ApiHelpers`
  (`render_save_result/2`, uniform errors). File downloads share
  `TaskyWeb.StorageServing` (local `send_file`/`send_download` vs. presigned
  302).
- Client params are parsed via `TaskyWeb.Params.int/1` and explicit atom
  whitelists — malformed input never crashes a LiveView. Two rules behind
  that: never interpolate a client value into an atom (`:"field_#{id}"` mints
  one permanent atom per distinct value, and the VM's atom table is a
  node-wide limit), and never hand a raw param to a query on an integer
  column (`Ecto.Query.CastError` is a 500 where a 404 is the honest answer).
  Resolve ids against what the mount actually registered instead.

## Frontend (`assets/js/`)

- One React/Tiptap component (`react/ExamContentEditor.jsx`) drives all
  editor modes (author, free document, sample solution, student, correction,
  read-only) via props. Splitting it into typed TS modules is the open
  Phase-4.6 item.
- Presets live in `react/editor/modes.ts`; the server picks one per surface and
  pushes it down as `data-editor-mode`. Three flags that used to be one:
  `hideAnswers` (no answer-field buttons), `protectAnswers` (load
  `PreventNodeDeletion`) and `hideCallout` (no Hinweisbox). The
  `freeDocument` preset needs the first without the other two, and serves both
  the teacher and the learner — only `uploadImage`, which just the authoring
  hook passes, tells the two apart.
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
