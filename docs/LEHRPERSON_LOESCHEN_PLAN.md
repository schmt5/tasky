# Umsetzungsplan: Lehrperson löschen (Admin)

## Ziel

Als Admin kann ich eine Lehrperson endgültig löschen.

- Ihre **Kurse, Lerneinheiten und Prüfungen** werden mitgelöscht, inklusive
  aller gespeicherten Dateien (lokal bzw. R2).
- **Im Katalog publizierte Kurse** (`catalog_published_at` gesetzt) bleiben
  erhalten. Sie gehen mitsamt ihren Lerneinheiten, Einschreibungen und Abgaben
  an die Admin-Person über, die das Löschen auslöst.
- Löschen ist auch dann möglich, wenn **Prüfungen mit Abgaben** existieren.
  Der Bestätigungsdialog weist aus, was verloren geht.

Es gibt keine Schemaänderung und keine Migration.

## Ausgangslage

### Fremdschlüssel auf `users`

| Tabelle.Spalte | `on_delete` | Folge beim Löschen der Lehrperson |
|---|---|---|
| `courses.teacher_id` | `delete_all` | Kurs weg → Einschreibungen und Tasks (über `tasks.course_id`) weg |
| `tasks.user_id` | `delete_all` | **Auch Tasks eines übertragenen Kurses**, wenn `user_id` nicht mit umgehängt wird |
| `exams.teacher_id` | `delete_all` | Prüfung samt Abgaben weg |
| `users_tokens.user_id` | `delete_all` | Sessions weg (offene LiveView-Sockets aber nicht) |
| `task_submissions.graded_by_id` (heute `feedback_by_id`) | `nilify_all` | Feedback bleibt, verliert die Autorin oder den Autor |

Wichtig: Beim Übertragen eines Kurses müssen sowohl `courses.teacher_id` als
auch `tasks.user_id` aller Tasks dieses Kurses umgehängt werden. Sonst nimmt
der Cascade über `tasks.user_id` die Lerneinheiten trotzdem mit.

### Bestehende Bausteine

- `Tasky.Policy.authorize_admin/1`: Gate für Admin-Aktionen.
- Admins sehen alle Kurse (`Courses.list_courses/1`, Zweig `"admin"`) und
  dürfen alles verwalten (`Policy.can_manage?/2`). Übertragene Kurse sind für
  die Admin-Person also ohne weitere Anpassung erreichbar.
- `Tasky.Uploads.delete_task_files_many/1`: Dateien vieler Tasks parallel
  löschen, best effort.
- `Tasky.Uploads.delete_exam_files/1`: Dateien einer Prüfung löschen. Ein
  `_many`-Pendant fehlt noch.
- `TaskyWeb.UserAuth.disconnect_sessions/1`: offene Sockets trennen.
- Vorbild für den Ablauf (IDs einsammeln, löschen, nach dem Commit Speicher
  leeren): `Courses.delete_course/1`, `Accounts.delete_student/2`.

## Schritte

### 1. `Tasky.Uploads.delete_exam_files_many/1`

Analog zu `delete_task_files_many/1`. Die Logik mit `async_stream_nolink`
wird in einen privaten Helper gezogen, den beide Funktionen nutzen. Best
effort, wirft nie, und läuft nicht innerhalb einer Transaktion.

### 2. `Accounts.teacher_deletion_summary(scope, teacher)`

Liest die Zahlen für den Dialog, nur für Admins:

- `courses_deleted`: Kurse ohne `catalog_published_at`
- `courses_transferred`: Liste der publizierten Kurse (Name, Anzahl Einheiten)
- `tasks_deleted`: Tasks mit `user_id == teacher`, die nicht in einem
  übertragenen Kurs liegen
- `exams_deleted`, `exam_submissions_deleted`
- `learners_affected`: verschiedene Lernende mit Einschreibung in einem
  gelöschten Kurs, einer Abgabe zu einer gelöschten Lerneinheit oder einer
  Abgabe zu einer gelöschten Prüfung

### 3. `Accounts.delete_teacher(scope, teacher)`

```
with :ok <- Policy.authorize_admin(scope),
     :ok <- deletable_teacher(scope, teacher) do
  Repo.transaction(fn ->
    1. Lehrperson mit SELECT … FOR UPDATE sperren. Das blockiert parallele
       Inserts von Kursen, Tasks und Prüfungen über den FK-Check, damit die
       eingesammelten IDs vollständig sind.
    2. IDs der publizierten Kurse lesen.
    3. UPDATE courses SET teacher_id = admin WHERE id IN published
    4. UPDATE tasks   SET user_id   = admin WHERE course_id IN published
    5. Restliche Task-IDs (user_id == teacher) und Exam-IDs einsammeln.
    6. Session-Tokens der Lehrperson lesen.
    7. Repo.delete(teacher). Den Rest erledigt der Cascade.
  end)
  # nach dem Commit, ausserhalb der Transaktion:
  disconnect_sessions(tokens)
  Uploads.delete_task_files_many(task_ids)
  Uploads.delete_exam_files_many(exam_ids)
end
```

`deletable_teacher/2` lehnt ab, wenn das Ziel nicht die Rolle `"teacher"`
hat (keine Admins, keine Lernenden) oder die eigene Person ist.

Die Rückgabe ist `{:ok, %{transferred: n, …}}` für die Flash-Meldung.

Die Dateien übertragener Kurse bleiben unangetastet. Sie liegen unter
`tasks/<id>/`, und die IDs ändern sich nicht.

### 4. UI in `TaskyWeb.Admin.UserEditLive`

- Neuer Abschnitt „Lehrperson löschen“, nur sichtbar bei
  `@user.role == "teacher"` und wenn es nicht die eigene Person ist.
- Ein Button (`id="delete-teacher-button"`) öffnet ein Modal im
  `<dialog class="modal modal-open">`-Pattern mit Escape- und Backdrop-Close.
  Beim Öffnen wird `teacher_deletion_summary/2` geladen.
- Inhalt des Modals:
  - was gelöscht wird (Kurse, Lerneinheiten, Lernende),
  - **Prüfungen hervorgehoben**: „N Prüfungen mit M Abgaben werden
    unwiderruflich gelöscht“,
  - welche Katalog-Kurse an die Admin-Person übergehen (Liste der Namen).
- Zur Bestätigung muss die E-Mail-Adresse der Lehrperson eingegeben werden
  (`<.form id="delete-teacher-form">` mit `<.input>`). Der Lösch-Button ist
  rot (Löschen ist nicht umkehrbar) und erst aktiv, wenn die Eingabe stimmt.
  Der Server prüft die Eingabe erneut.
- Nach Erfolg: `push_navigate` zur Benutzerliste mit einer Flash-Meldung wie
  „Lehrperson gelöscht, 2 Katalog-Kurse wurden dir übertragen.“

### 5. Tests

`test/tasky/teacher_delete_test.exs`:

- Nicht-Admin → `{:error, :unauthorized}`, keine Änderung.
- Ziel ist Lernende, Admin oder die eigene Person → Ablehnung.
- Nicht publizierter Kurs: Kurs, Tasks, Einschreibungen weg; Dateien unter
  `tasks/<id>/` weg.
- Publizierter Kurs: gehört danach der Admin-Person, Tasks haben
  `user_id == admin`, Einschreibungen und Abgaben samt Dateien bleiben.
- Task ohne Kurs: weg, Dateien weg.
- Prüfung mit Abgaben: weg, Dateien unter `exams/<id>/` weg.
- `teacher_deletion_summary/2` liefert die erwarteten Zahlen.

`test/tasky_web/live/admin/user_edit_live_delete_test.exs`:

- Abschnitt nur bei Lehrpersonen sichtbar, nicht beim eigenen Account.
- Modal zeigt die Zusammenfassung (über Element-IDs prüfen).
- Falsche Bestätigung löscht nichts, richtige leitet zur Benutzerliste weiter.

Zum Schluss `mix precommit` ausführen.

## Bewusst nicht im Umfang

- **Auswahl einer anderen Nachfolge-Person:** Übertragen wird immer an die
  auslösende Admin-Person. Das lässt sich später im Dialog ergänzen.
- **Katalog-Autor:** Im Katalog steht danach der Name der Admin-Person.
- **Uploads, die zeitgleich laufen:** Eine Datei, die erst nach dem Leeren
  des Präfixes geschrieben wird, bleibt als Waise liegen. Das ist dasselbe
  Restrisiko wie bei `delete_course/1`.
- **Bilder, die im Editor entfernt wurden:** Sie bleiben weiterhin bis zum
  Löschen der Einheit liegen. Das ist ein separates Thema.
