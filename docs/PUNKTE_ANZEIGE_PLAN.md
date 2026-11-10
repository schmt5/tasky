# Umsetzungsplan: Punkte pro Aufgabe anzeigen

## Ziel

1. **Lernende sehen pro Aufgabe, wie viele Punkte sie erreichen können**
   («4 Punkte» unter dem Aufgabentitel), während der Prüfung und in der
   Vorschau der Lehrperson.
   - Gezeigt wird nur das Total der Aufgabe, **nie die Verteilung auf die
     Antwortfelder** (`sample_solution_block_points`). Eine ungleiche
     Verteilung könnte ein Hinweis auf die Lösung sein.
   - Die Lehrperson kann das pro Prüfung ausschalten. Standardmässig ist es
     eingeschaltet. Der Schalter gilt für die Online- **und** die Papierversion.
2. **Die Musterlösung zeigt das Total der Prüfung**: «Total 24 Punkte ·
   7 Aufgaben», dazu ein Hinweis auf Aufgaben ohne Punkte.

Nur im Modus «Antwortfelder». Ein freies Dokument hat keine Aufgaben mit
eigenen Punkten und bleibt unverändert.

## Ausgangslage

| Was | Wo |
|---|---|
| Punkte pro Aufgabe, `%{part_id => points}` | `exam.sample_solution_points` |
| Verteilung auf Antwortfelder (bleibt geheim) | `exam.sample_solution_block_points` |
| Total der Prüfung | `Exams.total_points/1` ([exams.ex:1526](../lib/tasky/exams.ex)) |
| Aufgaben zerlegen, inkl. Rückfall auf `"q-N"` bei alten Dokumenten | `ExamDoc.split_content_into_parts/2` |
| Papierversion hängt «(4 Punkte)» an den Titel, **ohne Schalter** | `ExamPaper.with_points_in_headings/3` ([exam_paper.ex:235](../lib/tasky/exam_paper.ex)) |
| Antwortblatt der Lernenden (serverseitiges HTML) | `.answer_sheet` → `TaskyWeb.ExamDocHTML.render/2` |
| Prüfung der Lernenden | `TaskyWeb.Guest.ExamLive`, `answer_doc` = `submission.content` oder `exam.content` |
| Vorschau der Lehrperson | `ExamLive.Content`, Tab `vorschau`, dieselbe `.answer_sheet` |
| Zurückgegebene Prüfung zeigt «(2/4 P.)» unter dem Titel | `LearnerReturn.learner_part_points/2`, CSS `h3[data-points]` |

Die Rückgabeansicht läuft über den Tiptap-Editor, die Prüfung über
`ExamDocHTML`. Die beiden kommen sich also nicht in die Quere.

## Entscheide

- **Neue Spalte `exams.show_part_points` (boolean, Standard `true`).**
  Eine eigene Spalte statt eines Eintrags in einer Map, damit Kopieren, Tests
  und spätere Abfragen einfach bleiben. Das Hinzufügen mit Standardwert braucht
  keine Datenkonvertierung. Bestehende Prüfungen zeigen die Punkte damit sofort
  an, wie heute schon auf Papier.
- **Die Punkte werden beim Rendern dazugenommen, nicht in die Abgabe
  geschrieben.** `submission.content` bleibt unverändert. Ändert die Lehrperson
  die Punkte vor dem Start, sehen alle die neuen Werte. Während der Prüfung
  erscheinen Änderungen beim nächsten Laden der Seite (das Antwortblatt ist
  `phx-update="ignore"`). Das reicht.
- **Gleicher Ort wie bei der Rückgabe**: unter dem Aufgabentitel, klein und
  dezent. Nach der Rückgabe steht an derselben Stelle «2/4 P.».
- **Echter Text statt CSS `::after`**, damit Screenreader die Punkte vorlesen.
  Der Text kommt in ein eigenes Element nach dem `<h3>` und nicht in den Titel
  selbst. So bleibt die Frage-Beschriftung der Felder für Screenreader
  (`ctx.question`) unverändert.
- **Der Schalter liegt im Tab Musterlösung**, direkt bei der Total-Zeile. Dort
  vergibt die Lehrperson die Punkte, und dort entscheidet sie, ob die
  Lernenden sie sehen.

## Schritte

### 1. Schema und Kontext

- `mix ecto.gen.migration add_show_part_points_to_exams`:
  `add :show_part_points, :boolean, null: false, default: true`.
- `Tasky.Exams.Exam`: `field :show_part_points, :boolean, default: true`,
  dazu ein eigenes `part_points_display_changeset/2` (nur dieses Feld,
  `cast` + `validate_required`).
- `Exams.set_show_part_points(scope, exam, value)`: mit Policy-Prüfung wie bei
  den anderen Setzern im Kontext.
- `Exams.duplicate_exam_records/3`: das Feld mitkopieren.
- Eine Funktion, die beide Ansichten nutzen:

  ```elixir
  @doc "Max points per question the learners may see, or nil when hidden."
  def learner_visible_part_points(%Exam{answer_mode: "answer_fields", show_part_points: true} = exam),
    do: exam.sample_solution_points || %{}
  def learner_visible_part_points(%Exam{}), do: nil
  ```

  Sie liefert bewusst nur `sample_solution_points` und nie die Werte pro
  Antwortfeld.

### 2. Aufgabentitel markieren (`Tasky.ExamDoc`)

- Den Teil von `ExamPaper.with_points_in_headings/3`, der Aufgaben zerlegt
  und Titel ersetzt, nach `ExamDoc` auslagern, z. B.
  `ExamDoc.map_question_headings(doc, mode, fun(part_id, heading_node))`.
  Er übernimmt den Rückfall auf `"q-N"` (keine neuen ids erzeugen, siehe
  Kommentar in `exam_paper.ex`).
- `ExamDoc.put_part_points(doc, mode, points_map)` setzt damit auf jeden
  Aufgabentitel mit Punkten das Attribut `"maxPoints"`. Aufgaben ohne Punkte
  bleiben ohne Attribut.
- `ExamPaper` verwendet die ausgelagerte Funktion für die Papierversion
  weiter, ohne Änderung am Ergebnis.

### 3. Anzeige für Lernende (`TaskyWeb.ExamDocHTML`)

- `node(%{"type" => "heading"})`: Steht `attrs["maxPoints"]` auf einem
  Aufgabentitel, wird nach dem `<h3>` gerendert:

  ```html
  <p class="exam-doc__points" data-part-points>4 Punkte</p>
  ```

  Einzahl/Mehrzahl wie `ExamPaper.points_suffix/1` («1 Punkt», «4 Punkte»),
  Zahl über `Grading.format_points/1`.
- CSS in der Datei der `.exam-doc`-Styles: kleine Schrift, `text-stone-500`,
  `tabular-nums`, wenig Abstand zum Titel. Die Gestaltung lehnt sich an
  `h3[data-points]::after` in `exam_content_editor.css` an, damit Prüfung und
  Rückgabe gleich aussehen.
- `Guest.ExamLive`: `answer_doc` vor dem Rendern mit
  `ExamDoc.put_part_points(doc, exam.answer_mode, Exams.learner_visible_part_points(exam))`
  anreichern, nur wenn die Map nicht `nil` ist. **Nicht** in
  `submission.content` speichern. Prüfen, dass der Speicher-Hook
  (`ExamAnswersForm`) nur Feldwerte schickt und das angereicherte Dokument
  nirgends zurückgeschrieben wird.
- `ExamLive.Content`, Tab `vorschau`: dieselbe Anreicherung, damit die
  Vorschau zeigt, was die Lernenden sehen.
- Lerneinheiten rufen `put_part_points` nie auf und bleiben unverändert.

### 4. Papierversion respektiert den Schalter

- `ExamPaper.paper_doc/2`: neue Option `:show_part_points` (Standard `true`).
  Ist sie `false`, werden keine Punkte an die Titel gehängt.
- Die Option in beiden Aufrufen setzen: `ExamLive.Paper.assign_paper/2` und
  `ExamPaperPdf` ([exam_paper_pdf.ex:36](../lib/tasky/exam_paper_pdf.ex)).
- Die Zeilenzahl der Antwortfelder (`answer_block_points/2`) hängt weiter
  an den Punkten. Der Schalter betrifft nur, was gedruckt dasteht.
- «Punkte von X» im Kopf der Papierversion bleibt. Das Total verrät nichts.

### 5. Total und Schalter im Tab Musterlösung

Oben im Tab, über der ersten Aufgabe (nur wenn `not @free_document` und
`@part_views != []`), kommt eine schmale Karte im Stil der Punktekarten:

```
┌──────────────────────────────────────────────────────────────────────┐
│ Total 24 Punkte · 7 Aufgaben · ⚠ 2 ohne Punkte    [●] Lernenden zeigen │
│ Note 6 bei 22 Punkten                                                  │
└──────────────────────────────────────────────────────────────────────┘
```

- **Total**: Summe aus `@part_views` (`pv.max_points`). Sie wird aus den
  Assigns berechnet und aktualisiert sich damit sofort nach `set_max_points`
  und `adjust_max_points`, ohne zusätzliche Abfrage.
- **«ohne Punkte»**: Anzahl Aufgaben mit `max_points` `nil` oder `0`, in Amber.
  Fehlt nichts, entfällt der Teil. (Ein Sprung zur ersten solchen Aufgabe ist
  offen: Header und Werkzeugleiste kleben oben und würden das Ziel verdecken.)
- **«Note 6 bei …»**: nur wenn `exam.grading_max_points` gesetzt ist und vom
  Total abweicht.
- **Schalter «Punkte pro Aufgabe den Lernenden zeigen»**: `<.form
  for={@part_points_form} id={"part-points-display-form-#{@exam.id}"}
  phx-change="set_show_part_points">` mit `<.input type="checkbox">`,
  Formular über `to_form/2`. Ein Tooltip-Komponent (kein `title`) erklärt:
  «Auch auf der Papierversion. Die Verteilung auf die Antwortfelder bleibt
  verborgen.»
- Die Zeile scrollt mit (kein `sticky`), weil oben schon Header und
  Werkzeugleiste kleben. Mit einer dritten klebenden Leiste würde der Platz
  für den Editor zu knapp.
- IDs für Tests: `#solution-points-summary`, `#solution-points-total`,
  `#solution-points-missing`, `#part-points-display-form-<id>`.

## Tests

| Datei | Fälle |
|---|---|
| `test/tasky/exam_doc_test.exs` | `put_part_points` setzt `maxPoints` nur auf Aufgabentitel mit Punkten, findet `"q-N"` bei alten Dokumenten |
| `test/tasky/exam_paper_test.exs` | `show_part_points: false` → kein Suffix; Zeilenzahl unverändert |
| `test/tasky_web/exam_doc_html_test.exs` | `maxPoints` → `.exam-doc__points` mit «4 Punkte» / «1 Punkt»; ohne Attribut nichts; Feldbeschriftung ohne Punkte |
| `test/tasky_web/live/guest_exam_live_test.exs` | Punkte sichtbar; bei `show_part_points: false` nicht; bei ungleicher Verteilung erscheinen keine Werte pro Feld; `submission.content` bleibt ohne `maxPoints` |
| `test/tasky_web/live/exam_content_live_test.exs` | Total und «ohne Punkte» stimmen und folgen `set_max_points`; Schalter speichert; Vorschau folgt dem Schalter |
| `test/tasky_web/live/exam_paper_live_test.exs` | Papierversion folgt dem Schalter |
| Duplizieren (bestehender Test zu `duplicate_exam`) | `show_part_points` wird mitkopiert |

Getestet wird über `has_element?/2` mit den IDs bzw. Klassen oben, nicht über
den rohen HTML-Text.

## Commits

1. `feat(exams): let the teacher hide each question's points from learners`:
   Migration, Schema, Kontext, Duplizieren.
2. `refactor(exams): share question-heading mapping between paper and sheet`:
   Auslagerung nach `ExamDoc`, Papierversion unverändert.
3. `feat(exams): show learners what each question is worth`:
   `ExamDocHTML`, `Guest.ExamLive`, Vorschau, CSS.
4. `feat(exams): leave points off the paper version when hidden`
5. `feat(exams): total the sample solution's points`:
   Total-Karte und Schalter im Tab Musterlösung.

Am Schluss `mix precommit` (wegen des laufenden Dev-Servers mit
`MIX_ENV=test`).

## Nicht Teil dieses Plans

- Total oben auf dem Antwortblatt der Lernenden. Das wäre leicht zu ergänzen,
  falls gewünscht.
- Freies Dokument: Anzeige der Gesamtpunkte für Lernende.
- Punkte im Tiptap-Antwortweg (`ExamSubmissionEditor`, nur freies Dokument).
