# Robustness & Clean Architecture Plan

Status: **in progress** · Date: 2026-07-17 · Based on a full code audit (contexts, web layer, frontend, tests/tooling/config).

Bug-fix & robustness pass (2026-08-14) — a full audit of the newest features, the grading
pipeline and the student surface. Two findings mattered most and both were invisible:

- **CI had been permanently red**, so none of the gates below were actually gating.
  `mix format --check-formatted` could never pass (a HEEx line with a literal `·` before an
  inline `{expr}` was a formatter non-fixpoint — the space count grew by one on every run), and
  `mix dialyzer` exited 2 on an unreachable clause. It went unnoticed because `mix precommit`
  ran the *mutating* `mix format` and skipped dialyzer. Both fixed; `precommit` is now identical
  to `.github/workflows/ci.yml`, which Phase 0 had required all along.
- **Deleting an exam question silently depressed every student's mark.**
  `prune_orphan_block_points/3` never pruned `sample_solution_points` by surviving part id, so a
  deleted question kept inflating the grading denominator — a student scoring 8/8 got 4.25
  instead of 6.0, on screen and in the PDF.

Also fixed: the auto-corrector wrote `"incorrect"`, a verdict nothing downstream understood
(blocks rendered as ungraded and lost their ❌ on the next edit); a re-run overwrote verdicts the
teacher had entered by hand (now tracked via `auto_block_verdicts`); manual points were clamped
*before* rounding, so a value could exceed the block max and read as fully correct; `set_part_points/4`
stored unvalidated points (`"-5"`, `"1e3"`); enabling then clearing custom block points ratcheted the
part total up by 0.25 each round; three read-modify-writes ran without a row lock
(`save_exam_structure/3`, `Tasks.save_student_answers/3` — which let an autosave land *after*
hand-in — and `update_corrected_parts/2`); students could open draft and archived units of their
course by URL; the guest per-IP cap was bypassable over the websocket and the enrolment token was
only ~30 bits; several handlers crashed on crafted params (client-supplied `field-id` interpolated
into an atom, `String.to_integer/1`, a nil navigation index, a nil `solution_release_mode` hitting a
NOT NULL column); a bulk verdict rolled the whole batch back for one empty submission with nothing
shown to the teacher; partial exports were announced as clean successes and their timed-out
submissions lost their identity in the manifest; and a rejected answer upload left orphaned bytes in
storage. `Exams.apply_auto_correction/5` had no test coverage at all — it does now.

Progress (2026-07-19):
- **Phase 0 — done.** Green suite, CI (GitHub Actions), credo/dialyzer/sobelow/excoveralls wired, npm in `assets.setup`, repo hygiene, real README.
- **Phase 1 — done.** All 8 hotfixes implemented with regression tests: student-task IDOR (enrollment checked in `Tasks.get_task_for_student/2`), autosave permanent-failure classifier + keepalive unload flush + beforeunload guard, `crypto.randomUUID()` answer ids + paste dedupe (`withFreshAnswerIds`), SEB quit password via `:crypto` in one place, `ExamUploadField` validation fix, email-disabled documented (dead confirm-email route removed), `/uploads` pipeline hardening (nosniff, `default-src 'none'; sandbox`, CORP) + magic-byte sniffing + site-wide CSP (print-ready script moved into the bundle for it). Not yet deployed.
- **Phase 2 — done.** `Tasky.Policy` (admin sees everything, `:system` scope for trusted jobs), every `Exams`/`Tasks` mutator scope-checked in the context, unified `{:error, :unauthorized}`, exam status/enrollment_token no longer mass-assignable (explicit lifecycle transitions), crash-proof param parsing (`TaskyWeb.Params`), dead auth code deleted, no `Repo` under `lib/tasky_web/` (credo `ForbiddenModule` gate), shared `TaskyWeb.ApiHelpers` for the JSON controllers.
- **Phase 3 — done except 3.3's display side.** The data side of 3.3 is in: auto-correction persists authoritative `block_verdicts` (keyed by `answerId`) together with content, points and the auto-flag in **one** transaction (`Exams.apply_auto_correction/5`), so grading no longer depends on re-inferring the runner's verdicts. The ✅/🟡/❌ markers are still written into `corrected_content` as the visual representation; removing them (render-time decorations in the React viewers) is the remaining piece and belongs with the 4.6 editor split. 3.1 `Tasky.Grading` extracted and unit-tested (one Swiss mark formula for screen + PDF; the print divergence is gone). 3.2 verdicts re-keyed by stable `answerId`. 3.4/3.5 grading writes and bulk operations run in `BEGIN IMMEDIATE` transactions with in-transaction refetch (incl. submit gates, `set_block_verdict_bulk`, `mark/unmark_part_corrected_bulk`); stale-struct regression test added. 3.6 question headings carry stable `partId`s (client-stamped via `PartIdStamper`, server fallback `ExamDoc.ensure_part_ids/1`, paste dedupe; positional `q-N` fallback for not-yet-re-saved docs).
- **Phase 4 — mostly done.** 4.1 `Tasky.Storage` behaviour (Local adapter) is in and all file IO goes through it; exam/task deletion now removes stored bytes (orphaned-bytes bug fixed). 4.3 shared content-management UI extracted into `TaskyWeb.ContentComponents` (`tab_link`, `upload_field_form` with a `label_placeholder` attr, and the pure upload-field-draft helpers `new_field_draft`/`presence`/`put_draft_error`), consumed by both `exam_live/content.ex` and `task_live/content.ex` — the two were structural clones (byte-identical `tab_link`, `upload_field_form` differing only in one placeholder). Verified end-to-end in the browser (render + upload-field create/delete round-trip on the exam side). 4.4 the correction views already share all points/verdict **math** via `Tasky.Grading`; the last divergent copy (`format_max_points` in `correction_part_bulk.ex`) now delegates to `Grading.format_points`. Their verdict **pills** legitimately differ (segmented single-submission part view vs. standalone bulk-group buttons) and are intentionally not force-merged. 4.5 all React islands run on `createReactHook` (destroyed-after-await guard everywhere, corrupt `data-content` fails loudly instead of mounting an empty editor, shared flush handshake). 4.6 `ExamContentEditor.jsx` split (1569 → 237 lines) into a TypeScript `assets/js/react/editor/` (`extensions.tsx`, `icons.tsx`, `useAutosave.ts`, `Toolbar.tsx`, `constants.ts`, `ids.ts`, `modes.ts`, `types.ts`). 4.7 duplicate helpers killed (`get_progress_map_for_course`, `get_initials` ×3, `parse_points`/`format_points` via `Grading`). **Open: 4.2 — the student answer surface's shared *chrome* is extracted (`TaskyWeb.StudentComponents.student_tab_button`), but the upload-plumbing handlers (`handle_answer_progress`, `submission_files_by_field`, `refresh_submission_files`) still live in each of `guest/exam_live.ex` and `student/task_live.ex`; they diverge only by domain module (Exams vs Tasks) and the editability gate, so a shared extraction needs a small domain-adapter and was deferred as higher-risk-than-reward on the live app. The schema-level task/exam files dedup remains too.**
- **Phase 5 — done except 5.3.** 5.1 `Tasky.ExamDoc` extracted (pure doc algebra, unit-tested). 5.2 the `Exams` ↔ `BulkCorrectionRunner` cycle is broken (`CorrectionOrchestrator` subscribes to `"exam_events"`). 5.4's named change-tracking offender (`render_config_chip`) is a declarative component. 5.5 `ExportRunner` takes an injected `web` map (print URL + token signing) — no routing/signing in the domain. 5.6 "Kopie von" moved to the web layer; Gettext deliberately not adopted (single-language app; changeset messages stay in the schemas). 5.7 the update-then-broadcast dance is one `update_and_broadcast/2` helper. **Open: 5.3 (slicing the three fat LiveViews — `exam_live/content.ex`, `correction_part.ex`, `guest/exam_live.ex`), which depends on the Phase-4 shared components.**
- **Phase 6 — done (code side).** `Tasky.Storage.R2` (ReqS3, private bucket, presigned GETs via 302, HEAD existence check, prefix deletes, object metadata at PUT). Enabled with `STORAGE_ADAPTER=r2`; credentials validated at boot. **Needs an operator to provision the bucket/keys and verify upload → render → PDF end-to-end against R2.**
- **Phase 7 — done.** 7.1 per-exam singleton runner (Registry, queued re-runs, crash-safe terminal broadcast). 7.2 Gotenberg transient-error retries. 7.3 partial-success exports (`FEHLER.txt` manifest), `ExportJanitor` instead of sleeping cleanup tasks, download tokens sign an opaque id. 7.4 `printReady` gated on viewer render + image load (20 s fallback). 7.5 `CorrectionClient` and its config deleted.
- **Exam-readiness pass (2026-08-27) — done.** Four blockers found while auditing the exam path for a real graded exam with assigned participants in Safe Exam Browser. (1) **SEB is now enforceable server-side**: `Tasky.Exams.SebConfigKey` derives the SEB Config Key, `TaskyWeb.SebGuard` + its plug and `on_mount` hook check the `X-SafeExamBrowser-ConfigKeyHash` header on the exam page, the answer-file download *and* the guest autosave API (previously only a spoofable user-agent sniff, gating only the render). Per-exam mode `off`/`observe`/`enforce`, default `observe`, with a 15-minute kill switch and an accept-observed-hash override; `.seb` hardened (`sendBrowserExamKey`, admin password, URL filter, single display, keyboard lockdown, downloads derived from the exam and frozen at session open); quit password 6 digits → ~55 bits. `docs/SEB_PROBELAUF.md` is the operator procedure — **nothing may be switched to `enforce` before that dry run**. (2) **Grading bug**: `apply_auto_correction/5` froze `points_per_part` once any block was hand-graded while still refreshing the other blocks' verdicts and markers, so stored points contradicted stored verdicts; the total is now recomputed from what is actually stored, via the same helpers the manual path uses. (3) `grading_max_points` is validated in the context (a typo'd `-6` or `0` silently marked a whole class 1.0 / removed every mark), with DB check constraints behind it. (4) `submitted_at` exists — `updated_at` was never the hand-in time. Plus: `finished → running` reopen, so a misclicked "Prüfung beenden" is no longer terminal. **Still open and deliberately deferred**: the own-submission check exists only in `Guest.ExamLive`, not in the three guest controllers; `delete_upload_field/2` has no exam-status guard; no attempt audit trail beyond `submitted_at`; no real concurrency tests.
- **Phase 8 — partially done.** 8.2 fixtures for exams/courses/classes exist. 8.3 unique (exam_id, email) index (+ dedupe migration), task status inclusion, 5 MB content-JSON caps, enrollment-token collision retry, per-IP rate limit on the guest enrollment routes. 8.4 **superseded**: the database moved from SQLite-on-a-volume to **Neon Postgres**, so Litestream was removed entirely and backups/PITR are the provider's. 8.5 `PHX_HOST` fails fast, Dockerfile on 1.18.4/OTP 28 (matching CI); the `name` volume rename is moot — with Neon plus R2 the machines are stateless and the volume is gone. 8.6 `ARCHITECTURE.md` rewritten. 8.1 route-level **authorization matrix** (`test/tasky_web/authorization_test.exs`, per role across the JSON APIs, downloads and browser scopes — it caught and fixed a real bug: the role plugs crashed with "flash not fetched" on JSON pipelines instead of returning 401/403) and an **excoveralls ratchet** (`coveralls.json`, `minimum_coverage: 25`, enforced by `mix coveralls` in CI — raise it as coverage grows). Deeper per-view coverage remains a standing chore rather than a tracked plan item.

Decisions taken (2026-07-17):
- **The app is in beta: no backward compatibility, no data migrations.** Existing data may be reset at any time — schema and storage-format changes are made directly, without migration paths, backfills, or rollback grace periods.
- **All stored files move to Cloudflare R2** (content images, teacher attachments, student submission files), accessed via **presigned URLs** from a private bucket (Phase 6).
- **Email stays disabled for now** — no production mailer; document it, don't build it.
- **`Tasky.AI.CorrectionClient` gets deleted** — bulk correction continues on `StringComparator`; the Anthropic client can be rebuilt when actually needed.
- **Admin sees everything** — admins can view and manage all teachers' exams, tasks, and courses; `Tasks` gets opened up to match `Exams`, one rule in one place.
- **Single deploy target** — everything lands on `main` and deploys to the one Fly app **`learningline`** (`fly.toml`), running on Neon Postgres + R2 with stateless machines.
- **TypeScript during the frontend split** — new/split modules are written as `.ts`/`.tsx` (esbuild handles TS natively); typed Tiptap-doc and API payload shapes.
- **No job queue** — background work stays on supervised in-process Tasks, hardened in Phase 7; a job lost to a restart is re-triggered by the teacher.

Guiding idea: **stabilize → secure → fix the data model → deduplicate → slice the god modules → harden the runtime → lock it in with tests and ops.** Each phase leaves the app deployable; later phases build on the safety net of the earlier ones.

---

## Phase 0 — Stabilize the baseline (make the ground solid)

Nothing can be safely refactored while the test suite is red and there is no CI.

1. **Fix the red test suite** — all 14 failures share one cause: fixtures call `Exams.create_exam_submission/2` without the now-required `email` (added in `20260608120000_add_email_to_exam_submissions.exs`). Update fixtures in `test/tasky/exams_test.exs` and `test/tasky_web/live/guest_exam_live_test.exs`, add an `exams_fixtures.ex` module.
2. **Wire npm into the build** — `mix assets.setup` / `assets.deploy` never run `npm install --prefix assets`; a fresh checkout or CI fails the bundle. Add it to the aliases in `mix.exs`.
3. **Add static analysis**: `credo` (strict), `dialyxir`, `sobelow`, `excoveralls`. Fix or explicitly ignore initial findings so the tools run clean.
4. **Add CI** (GitHub Actions — repo is on GitHub, `main` is the working branch): compile with `--warnings-as-errors`, `mix format --check-formatted`, credo, sobelow, `mix test`, assets build. Make `mix precommit` and CI identical.
5. **Repo hygiene**: delete/archive the ~20 stale AI-generated root markdown files (`IMPLEMENTATION_COMPLETE.md`, the 4 overlapping ROLES_* docs, the 4 overlapping *SUBMISSIONS* docs, `QUICK_TEST.md`, `ROUTER_EXAMPLE.md`, …), dead scripts (`test_webhook.sh`, `verify_courses.exs` — both reference the removed Tally integration). Keep `AGENTS.md`, `ARCHITECTURE.md` (rewrite later), move living docs into `docs/`. Write a real `README.md`.

**Exit criteria:** green suite, CI gate on every push, `mix precommit` passes.

---

## Phase 1 — Security & data-loss hotfixes (small, surgical, urgent)

These are shippable individually and should not wait for the big refactoring.

1. **IDOR: student task access** — `Student.TaskLive.mount` (`lib/tasky_web/live/student/task_live.ex:555`) has no enrollment check: any student can open, answer, and complete any teacher's task via `/student/tasks/:id`. Mirror the check that already exists in `Student.TaskAnswersApiController` (`Courses.enrolled?`), ideally as `Tasks.get_task_for_student(scope, id)`.
2. **Autosave infinite-retry on session expiry** — the editor's retry classifier (`assets/js/react/ExamContentEditor.jsx:401`) treats 401/403 and HTML-redirect responses as retryable → infinite loop, nothing saves, student thinks it's saving. Treat 401/403/non-JSON as permanent with a "please reload" message.
3. **Unload-safe flush** — the visibility/unmount flush uses plain `fetch` without `keepalive: true`; closing the tab can drop the last second of a student's exam answer. Add `keepalive` + a `beforeunload` guard while unsaved.
4. **`answerId` collisions** — `generateAnswerId()` draws from only 9,000 values and copy-paste duplicates IDs verbatim; colliding answer fields silently merge answers in grading. Use `crypto.randomUUID()` (or long random ids) and de-duplicate on paste.
5. **SEB quit password RNG** — `:rand.uniform` used for a security control, duplicated in `lib/tasky/exams.ex:87` and `lib/tasky_web/live/exam_live/cockpit_config.ex:181`. Generate via `:crypto.strong_rand_bytes` in exactly one place.
6. **Exam upload-field type validation bug** — `ExamUploadField.validate_allowed_types` still has the "untouched empty default" bug that `TaskUploadField` already fixed (`lib/tasky/exams/exam_upload_field.ex:33`).
7. **Document email as disabled** — `config/demo.exs` (the de-facto prod env) and `prod.exs` use `Swoosh.Adapters.Local`: production emails go nowhere. Decision: email is not needed yet. Verify no user-facing flow depends on delivery (magic links, confirmation), hide/disable any that do, and note the state in the README so it isn't rediscovered as a bug.
8. **Interim hardening of the public `/uploads` scope** — router scope at `lib/tasky_web/router.ex:94` has no pipeline: teacher attachments (exam material) are world-readable forever with `cache-control: immutable`. The real fix is the private R2 bucket with presigned URLs (Phase 6); until then, add `nosniff`/secure headers to the scope and magic-byte sniffing on image upload so the interim exposure is bounded. Also add a Content-Security-Policy to the browser pipeline (sobelow's one high-confidence finding, ignored in `.sobelow-conf` until this ships — verify the Tiptap editors, LiveView websocket, and the Gotenberg print page against it).

**Exit criteria:** each fix has a regression test; deployed to production.

---

## Phase 2 — Authorization & context API normalization

Make "who may do what" enforceable in one layer instead of three drifting ones.

1. **Scope every `Exams` mutator.** `update_exam/2`, `delete_exam/1`, `update_exam_status/2`, `set_block_verdict/4`, `save_exam_structure/2`, … take no scope at all; authorization only holds if every caller fetched via `get_exam!/2` first. Add `scope` as the first argument everywhere, checked inside the context.
2. **Unify failure modes.** `Tasks` mixes `true = task.user_id == scope.user.id` (crash) with `{:error, :unauthorized}` and silent `[]` returns. Standardize on `{:error, :unauthorized}` (or a raise-only `!` convention) across both contexts; make "unauthorized" distinguishable from "empty".
3. **Unify the scoping model.** `Exams.get_exam!` lets admin see all; `Tasks.get_task!` locks even admins out. Decided rule: **admin sees and manages everything**. Encode it once (a small `Tasky.Policy` module or shared scope helpers) and apply it to both contexts — `Tasks` opens up to match `Exams`.
4. **Remove raw `Repo` from the web layer.** Add context accessors — `Exams.get_submission!(exam, id)`, `Exams.list_exam_submissions(exam, order: :name)`, `Tasks.get_submission!/2` — and replace direct `Repo`/Ecto usage in `correction_part.ex`, `correction_part_bulk.ex`, `print.ex`, `student/task_live.ex`, `admin/user_edit_live.ex`, the file controllers and API controllers.
5. **API controller boilerplate** — the 6+ content/image API controllers each re-implement load-authorize-translate_errors. Extract a shared plug/`action_fallback` so new endpoints can't forget the auth step.
6. **Clean up dead/misleading auth code** — `on_mount(:require_sudo_mode)` is a no-op stub that always continues; either implement or delete. Delete the pass-through `TaskyWeb.RoleHelpers`.
7. **Mass-assignment** — stop casting `:status` and `:enrollment_token` in the generic `Exam.changeset`; give status transitions their own function with an allowed-transitions check.
8. **Crash-proof param handling** — `String.to_existing_atom` on user params (`grading.ex:433`, `cockpit.ex:516`) and bare `String.to_integer` (`correction_part_bulk.ex:649,706`) crash the LiveView on malformed input. Parse via explicit whitelists / `Integer.parse` with graceful fallback.

**Exit criteria:** no `Repo.` calls under `lib/tasky_web/` (enforce via credo check), every context mutator takes a scope, authorization tests per role for the critical routes.

---

## Phase 3 — Grading domain: one source of truth

The most fragile core design: verdicts are stored as emoji (✅/🟡/❌) appended to document text and re-inferred by regex, keyed by *position*, mutated without transactions. This phase makes grading correct by construction.

1. **Create `Tasky.Grading`** (pure domain module): quarter-point rounding (currently duplicated 5× with divergent behavior), verdict semantics (`effective_verdict`, `awarded_points`, toggle rules), part/total computation, and the Swiss mark formula — which today exists twice with different rounding (`grading.ex:586` vs `print.ex:206`) and can print a different mark on the PDF than the grading screen shows.
2. **Stable verdict keys.** Verdicts are keyed `"part_id:index"` (positional) while points use stable `answer_id`s; inserting one answer block shifts every existing verdict of every submission. Re-key `block_verdicts` by `answer_id` directly — no migration of existing correction data (beta rule; old corrections may be reset).
3. **Markers become render-only.** `block_verdicts` is the single source of truth; the ✅/🟡/❌ markers in `corrected_content` are derived at render time (client-side, consistent with the existing rendering architecture), never parsed back. Remove the regex-inference path in `NodePatcher`/`Exams`.
4. **Transactional grading writes.** `set_block_verdict`, `set_part_points`, `update_corrected_part_content` do read-modify-write on three JSON columns with no transaction — a teacher clicking during a bulk-correction run silently loses verdicts. Wrap in `Repo.transaction(mode: :immediate)` with in-transaction refetch, exactly as `save_sample_solution_part` already does. Give the submit gates the same treatment: `submit_exam_submission` and `complete_task` check `missing_required_uploads` and then write non-transactionally (TOCTOU).
5. **Transactional bulk operations.** Move `toggle_part_corrected`, `set_group_verdict`, `set_group_verdict_manual` (currently N×M one-by-one writes in `correction_part_bulk.ex` event handlers) into single transactional context functions.
6. **Stable part ids.** Part ids are positional (`"q-1"`): reordering questions re-keys sample-solution points, AI config, and corrections exam-wide. Give parts stable ids persisted in the doc structure (coordinate with the Tiptap document format). No compatibility shim for old docs — exams saved before this change may need re-saving or resetting.

**Exit criteria:** `Tasky.Grading` fully unit-tested (property tests for rounding/marks), concurrent-write test for verdicts, one mark formula, no emoji parsing in business code.

---

## Phase 4 — Deduplicate the parallel worlds (tasks ↔ exams, guest ↔ student)

The file feature, submissions UI, and editors were built twice. Collapse them before they diverge further.

1. **Shared files subdomain** (~400 duplicated lines): attachments, upload fields, submission files, and the `Tasky.Uploads` save/path/delete variants are near-verbatim copies between tasks and exams. Extract a parameterized module (schema + path segment); the exams side inherits the task-side bug fixes for free. **Design it against a `Tasky.Storage` behaviour** (`put/get_url/delete` with a `Local` adapter first) — this is the seam the R2 cutover in Phase 6 plugs into, so storage gets swapped once, not per feature. While in here, **fix the orphaned-bytes bug**: `delete_exam`/`delete_task` cascade the DB rows but never remove `uploads/exams/<id>/**` / `uploads/tasks/<id>/**` — deletion goes through the shared module so file bytes are cleaned up too.
2. **Shared "student answer surface"** — `guest/exam_live.ex` and `student/task_live.ex` duplicate the upload plumbing, the three-state submit-flush modal, and `student_tab_button` nearly line-for-line. Extract LiveComponents / a shared handler module.
3. **Shared content-management UI** — `exam_live/content.ex` and `task_live/content.ex` are structural clones (tabs, upload-field drafts, attachment progress). One LiveComponent per concern (attachments panel, upload-fields panel).
4. **Shared verdict/points UI** — verdict pills, manual-points input, kbd legend duplicated between `correction_part.ex` and `correction_part_bulk.ex`; both consume `Tasky.Grading` from Phase 3.
5. **JS hook factory** — 8 hook files repeat the same dynamic-import/createRoot/JSON-parse/destroy boilerplate; `flushAndReport` is copied verbatim between two hooks. One `createReactHook(loadComponent, mapProps)` factory (~250 lines removed), with a destroyed-after-await guard (currently only 1 of 8 hooks handles this) and a loud failure path when `data-content` JSON is corrupt (today it silently renders an empty editor whose next autosave overwrites the server copy).
6. **Split `ExamContentEditor.jsx`** (1569 lines → modules) **and move to TypeScript in the same pass**: `extensions/` (answer nodes, teacher comment, deletion guards, clipboard), `icons.tsx`, `useAutosave.ts`, `Toolbar.tsx`, `constants.ts`, thin composing component — all new/split files as `.ts`/`.tsx` (esbuild compiles TS with zero extra config; enable `strict` in tsconfig and add a `tsc --noEmit` check to CI). Type the two critical contracts explicitly: the Tiptap doc JSON shape and the API payloads (`{content}` vs `{nodes}`). Replace the 14-prop mode matrix with explicit mode presets over one `useExamEditor` core.
7. **Kill duplicated helpers**: `get_progress_map_for_course` (exists in both `tasks.ex` and `courses.ex`), `parse_points`/`format_points` (5–6 divergent copies), `get_initials`, sticky-shadow logic (hook + inline copy).

**Exit criteria:** one implementation each for files, submit flow, verdict UI, editor hooks; measurable LOC reduction; behavior covered by tests written before extraction.

---

## Phase 5 — Slice the god modules

With duplication gone and the domain extracted, the big files become mechanical to split.

1. **`lib/tasky/exams.ex` (1700 lines) → focused modules:**
   - `Tasky.ExamDoc` — pure Tiptap document algebra (`split_content_into_parts`, `assemble_parts_into_content`, `answer_block_labels`, …); pure functions, trivially unit-testable.
   - `Tasky.Grading` — already exists after Phase 3.
   - `Tasky.Exams.Files` — from Phase 4's shared subdomain.
   - `Tasky.Exams.Enrollment` — guest enrollment/session lifecycle.
   - `Tasky.Exams` remains the facade: CRUD, authz, PubSub.
2. **Break the `Exams` ↔ `BulkCorrectionRunner` circular dependency** — the runner calls back into `Exams` while `Exams` starts the runner from inside `do_submit_exam_submission`. Move the "submission submitted ⇒ start correction" trigger to an orchestration point above both (PubSub subscriber or explicit caller).
3. **Split the fat LiveViews** using the components from Phase 4: `exam_live/content.ex` (1175) into per-tab LiveComponents; `correction_part.ex` (1125) and `correction_part_bulk.ex` (877) become thin views over `Tasky.Grading`; `guest/exam_live.ex` (922) render `cond` with six UI states into function components.
4. **Consistent view idioms** — replace `render_*(assigns)` private-function calls (breaks change tracking, e.g. `render_config_chip` building `assigns = %{}` manually) with declarative function components + `attr`.
5. **Move web concerns out of `ExportRunner`** — it signs `Phoenix.Token`s and builds URLs; inject those from the web layer.
6. **Extract presentation strings** — German user-facing strings in contexts ("Kopie von", "Frage N", client error messages) move to the web layer or Gettext.
7. **Unify the broadcast-after-update boilerplate** — the hand-rolled `case ... {:ok, x} -> broadcast; result` pattern is copied ~8× across `exams.ex`/`tasks.ex`; one shared helper ends the divergence risk.

**Exit criteria:** no module over ~500 lines in `lib/tasky/`, LiveViews contain UI state only, credo module-length check enforced.

---

## Phase 6 — Storage cutover to Cloudflare R2

All stored files (content images, teacher attachments, student submission files) move from the Fly volume to a **private R2 bucket accessed via presigned URLs**. This permanently fixes the world-readable `/uploads` problem and removes all file state from the machines (only the SQLite DB remains on the volume). Depends on the `Tasky.Storage` seam from Phase 4.1.

1. **`Tasky.Storage.R2` adapter** implementing the behaviour from Phase 4.1, using `ReqS3` (R2 is S3-compatible; the project standard is Req). Config via `runtime.exs`: account id, bucket, access key/secret — validated at boot in prod. One bucket (`tasky`) for the single `learningline` app.
2. **Presigned-URL delivery.** Keep stable app routes as the URLs the client sees (`/uploads/...`, download routes); the controller checks authorization, then 302-redirects to a short-lived presigned GET. This means **no rewriting of image URLs stored inside Tiptap doc JSON** — stored docs keep working. The immutable public cache-control goes away; signed URLs expire instead.
3. **Uploads stay through Phoenix** (LiveView `allow_upload` and the image API controllers already handle validation/authz); the storage adapter streams to R2 instead of `File.cp`. Direct-to-R2 presigned uploads are a later optimization, not part of this phase.
4. **PDF/print pipeline check**: Gotenberg's Chrome must be able to fetch images during render — presigned URLs work for it, but verify expiry (exports render up to N × 120 s serialized; sign with a generous TTL or sign per-render).
5. **Cutover, not migration**: flip the adapter via config and start fresh on R2 — existing volume files are not migrated (beta rule). Delete the local-disk file-serving code paths in the same change instead of keeping them as fallback.
6. **Cleanup semantics**: wire all delete paths (field/attachment/submission-file deletes, and the exam/task-deletion cleanup from Phase 4.1) through the adapter so R2 objects don't leak; log failed deletes.

**Exit criteria:** no app-served file bytes from local disk in prod, presigned links expire, upload → render → PDF export verified end-to-end against R2.

---

## Phase 7 — Background jobs & external services hardening

1. **Bulk correction singleton per exam** — today `start_for_exam` spawns an unsupervised-result temporary task on every trigger; overlapping runs on the same exam interleave writes and emit contradictory progress streams, and a crash outside the per-job rescue never broadcasts `:bulk_correction_done` (UI hangs forever). Use a `Registry`-keyed process per exam with a `try/after`-guaranteed terminal broadcast.
2. **Retries with backoff** — `Gotenberg` does a single `Req.post` per render; use Req's built-in `retry:` options for 429/5xx/timeouts. (`CorrectionClient` would have needed the same, but it gets deleted in step 5.)
3. **Partial-success exports** — `ExportRunner.partition_results` throws away 29 good PDFs because 1 failed; deliver the ZIP with a failure manifest instead. Replace the `:timer.sleep(600_000)` cleanup task with a small janitor (`Process.send_after` + startup scan) so tmp ZIPs don't leak across restarts. Stop signing the absolute filesystem path into `ExportDownloadToken` — sign an ID resolved server-side instead.
4. **PDF readiness race** — `window.printReady` fires after a fixed 1 s timeout while the read-only React/Tiptap roots may still be loading chunks: cold Gotenberg produces blank/partial PDFs with no error. Gate `printReady` on every viewer root signaling rendered; consider a trimmed static renderer for the read-only path (stays client-side per the architecture decision).
5. **Delete `CorrectionClient`** — it is live-looking dead code (bulk correction actually uses `StringComparator`) with a hardcoded model/URL. Decision: remove it, its `ANTHROPIC_API_KEY` config, and the AI-specific parts of `ai_correction_config` it alone consumed; keep `NodePatcher`/`StringComparator`, which do the real work. Rebuild a client cleanly if AI correction returns.
6. **No job queue (decided)** — background work stays on supervised in-process Tasks; a job lost to a machine restart is simply re-triggered by the teacher. Document this tradeoff; revisit Oban only if exam-time reliability complaints appear.

**Exit criteria:** no orphaned progress UIs, exports survive single failures, chaos test (kill Gotenberg mid-export) behaves gracefully.

---

## Phase 8 — Test depth & operations

1. **Coverage for the critical money-paths** (currently zero tests): the correction LiveViews, all API controllers (including guest autosave), `Courses`, `Classes`, `NodePatcher`, `ExportRunner`, `SebConfig`, the file controllers (authorization matrix per role). Target: every route has at least an authorization test; every context function a happy-path + failure test. Track with excoveralls; set a ratchet (coverage may not decrease).
2. **Fixtures** — add `exams_fixtures.ex`, `courses_fixtures.ex`, `classes_fixtures.ex`; stop building test data inline.
3. **Data-integrity constraints**: unique index on exam-submission identity (`exam_id` + email/token) to prevent duplicate guest enrollment; upper bound on grade points; `:status` inclusion validation on `Task`; size limits on client-controlled content JSON; retry loop for the 6-char enrollment-token collision. Added directly — conflicting existing rows may simply be deleted (beta rule). Add basic rate limiting on the guest exam-token routes (tokens are guessable-by-brute-force short strings and also end up in logs/history).
4. ~~**SQLite operations**: add Litestream replicating to R2.~~ **Superseded** — the database moved to **Neon Postgres**, which owns backups and point-in-time restore. Litestream, the entrypoint wrapper and the Fly volume were all deleted. What this bought beyond backups: no single-writer bottleneck, and stateless machines. What it costs: read-check-then-write paths now need explicit row locks instead of SQLite's `BEGIN IMMEDIATE` — see the lock rules in `ARCHITECTURE.md`.
5. **Runtime config validation**: fail fast (or log loudly) when `PHX_HOST` or the R2 credentials are unset in prod instead of silently defaulting (`PHX_HOST` currently defaults to `example.com`). Rename the placeholder-ish `name` volume/db naming in the Fly configs; fix or remove the dangling `deploy/gotenberg/` docker-compose reference. Align the Elixir/OTP versions: dev and CI run 1.18.4/OTP 28 while the Dockerfile still pins 1.16.3/OTP 26 — bump the Dockerfile so prod builds with the same toolchain that is tested.
6. **Rewrite `ARCHITECTURE.md`** to describe the post-refactoring reality (context map, grading model, rendering pipeline, deployment) and delete the remaining stale docs.

**Exit criteria:** coverage ratchet in CI, provider-managed backups, honest architecture doc.

---

## Sequencing notes

- Phases 0 and 1 are quick and independent — do them first, in order.
- Phase 2 before 3: scoped context functions make the grading refactor testable.
- Phase 3 touches the stored data formats (verdict keys, part ids) — with the beta rule there's no migration risk, only the note that pre-change corrections/exams may need resetting.
- Phases 4 and 5 are large but mechanical once 2–3 are done; they can be interleaved per-feature (e.g. files first, correction UI second).
- Phase 6 (R2) requires the storage seam from Phase 4.1 but not the rest of Phase 4/5; it can start as soon as the shared files module exists.
- Phases 7 and 8 can partially run in parallel with 4–6; the CorrectionClient deletion (7.5) can even be pulled into Phase 0 cleanup if desired.
