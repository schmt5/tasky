# Plan: Replace Tally forms in courses with the Tiptap editor + file uploads

> **Status (2026-07-16): implemented.** All 5 phases are done, incl. Tally
> removal and the drop-columns migration. Verified E2E in the browser:
> author → publish → student answers/uploads/completes → teacher sends back →
> student revises → teacher approves.

## Decisions (from interview, 2026-07-15)

- **Field scope:** Learning units get rich Tiptap content **plus interactive answer fields** (answerBlock, Lückentext, MC checkboxes) — but **no** sample solutions, points-per-field, or AI/bulk correction. The teacher reads the student's answers and gives feedback.
- **Completion flow:** Student marks a unit complete (gated on required uploads). Teacher reviews, gives feedback, and can **approve** or **send back** (student can edit + re-complete). Uses existing `review_approved` / `review_denied` statuses.
- **Grading:** Feedback text only. `TaskSubmission.points` stays unused.
- **Tally:** Removed entirely in a final cleanup phase. No production data to preserve — destructive migrations are fine.
- **Upload slots:** Separate section below the content (reuse the `ExamUploadField` pattern), **one file per slot**, re-upload replaces.
- **Export/print:** The Tally-based `/courses/:id/export` page is dropped for now.

## Defaults chosen (veto if wrong)

- Student answers live in a full copy of the doc on the submission (`task_submissions.content`), exactly like `ExamSubmission.content` — reuses `LockExamContent` and the autosave engine unchanged.
- On `completed`, the student's editor becomes read-only; on `review_denied` it unlocks again.
- Teacher-side saves go through new authenticated JSON endpoints (same pattern as `/api/exams/:id/content`), student-side through a session-authenticated endpoint (no guest tokens — course students are logged in).
- `tasks.status` draft/published semantics stay (draft = invisible to students), `locked` stays.
- Existing PubSub topics (`student:{id}:submissions`, `course:{id}:progress`) are preserved so all live progress views keep working.

---

## Phase 1 — Data model & context groundwork

1. **Migration(s):**
   - `tasks`: add `content :map`; (keep `link`/`tally_form_id` for now — dropped in Phase 5).
   - `task_submissions`: add `content :map` (student answer doc).
   - New tables mirrored from the exam trio: `task_attachments` (teacher files), `task_upload_fields` (label, instruction, allowed_types, required, position), `task_submission_files` (unique on `(task_submission_id, task_upload_field_id)`).
2. **Schemas:** extend `Tasky.Tasks.Task` and `TaskSubmission`; add `TaskAttachment`, `TaskUploadField`, `TaskSubmissionFile` (adapted copies of `Tasky.Exams.ExamAttachment` / `ExamUploadField` / `ExamSubmissionFile`).
3. **`Tasky.Uploads`:** add task-scoped entry points (`save_task_image/2`, `save_task_attachment/3`, `save_task_submission_file/…`) reusing the generic internals; storage layout `uploads/tasks/:task_id/{images, attachments, submissions/:submission_id}`.
4. **`Tasky.Tasks` context:**
   - `save_task_content/2` (runs `Tasky.Correction.AnswerKey.ensure_ids/1` so answer nodes get stable `answerId`s).
   - Attachment + upload-field CRUD; `put_submission_file/3` (upsert, delete old bytes); `missing_required_uploads/1`.
   - `save_student_answers/3` (skeleton-validated like exams? minimal: store the doc), `complete_task/2` gated on required uploads, `approve_submission/2`, `deny_submission/2` (reopens editing), `save_feedback/3`.
   - All mutations keep broadcasting on the existing PubSub topics.
5. **Context tests** for the new functions and status transitions.

## Phase 2 — Teacher authoring

1. **API endpoints:** `PUT /api/tasks/:id/content` (→ `save_task_content`), `POST /api/tasks/:id/images` (→ `Uploads.save_task_image`), behind `require_admin_or_teacher` + task-ownership check. Extend `assets/js/react/api.js`.
2. **JS hook:** `task_content_editor_hook.jsx` mounting `ExamContentEditor` with the task endpoints (the component itself is reused untouched; only `save`/`uploadImage` callbacks differ). Register in `app.js`.
3. **Replace `CourseLive.Add`:** simple "Neue Lerneinheit" form (name) that creates the Task and redirects to the new edit page. Remove the Tally form picker + webhook creation.
4. **New task edit LiveView** (modeled on `ExamLive.Content`): tab **Inhalt** (Tiptap editor incl. answer-field toolbar buttons) and tab **Dateien** (LiveView uploads for attachments + CRUD for upload fields with allowed-type chips via `FileComponents`).
5. **`CourseLive.Show`:** link tasks to the edit page, replace the "Tally Form nicht veröffentlicht" badge with a plain draft/published toggle. Reorder/lock/delete stay as-is.

## Phase 3 — Student experience

1. **Rewrite `Student.TaskLive`:** drop the Tally iframe/hook. Mount the editor in student mode (doc = teacher content merged with the student's saved answers; `LockExamContent` restricts input to answer fields). New hook + endpoint `PUT /api/student/tasks/:id/answers` writing `task_submissions.content` (session-authenticated, enrollment-checked, rejected once completed/approved).
2. **Files UI:** teacher attachments as a download list; upload-slot panel with one LiveView upload config per field (`accept` from the type registry, `max_entries: 1`, auto-upload, replace-on-reupload), required-marker.
3. **Mark complete:** button using the `flush-before-submit` → `submit_check_result` handshake from exams; server verifies `missing_required_uploads/1` == [] before flipping to `completed`; editor switches to read-only.
4. **Review states:** show "eingereicht/abgeschlossen" card; on `review_denied` show the teacher feedback and unlock editing + re-complete; on `review_approved` show the final feedback card.
5. **Syllabus (`Student.CourseLive`):** adapt status badges/stats for the review states; live updates via existing PubSub subscriptions (should mostly keep working).

## Phase 4 — Teacher review & feedback

1. **Rework `TaskLive.Progress`:** remove all Tally API fetching. The submission view shows the student's answer doc via the read-only viewer hook (`ExamReadOnlyViewer` pattern) + their uploaded files.
2. **File download routes:** teacher route `GET /tasks/:id/submissions/:submission_id/files/:file_id` (scope-checked) and student re-download of their own file; extend `UploadController`/new controller following `SubmissionFileController`.
3. **Feedback + verdict:** feedback textarea (kept) + **Approve** / **Send back** actions driving the status transitions and PubSub broadcasts.
4. **`CourseLive.Progress` grid:** add the awaiting-review / denied states to the cell rendering.

## Phase 5 — Tally removal & cleanup

1. **Delete code:** `Tasky.Tally.Client`, `TallyWebhookController` + route + `:webhook` pipeline, `RawBodyPlug` (+ endpoint wiring), `UserLive.TallySettings` + route, Tally section in `UserLive.Settings`, `.TallyEmbed` remnants, `CourseLive.Export` + route, home-page banner, nav link in `layouts.ex`, `.no-tally-notice` CSS.
2. **Migration:** drop `tasks.tally_form_id` (+ index), `tasks.link`, `task_submissions.tally_response_id` (+ index), `users.tally_api_key`; remove the matching schema fields/changesets (`tally_api_key_changeset`, Accounts fns).
3. **Config/env:** remove `:tally_signing_secret` / `:tally_api_key` from `runtime.exs` + `dev.exs`; note `TALLY_*` env vars can be deleted from deployments.
4. **Tests/docs:** delete `tally_webhook_controller_test.exs` and the `TALLY_*.md` docs; update `COURSES_GUIDE.md` / `ARCHITECTURE.md` to the new flow.
5. **Verification:** full `mix test`, then manual E2E: author a unit with text + Lückentext + attachment + required upload slot → student fills, uploads, completes → teacher sends back → student fixes → teacher approves; check syllabus + progress grid live-update throughout.
