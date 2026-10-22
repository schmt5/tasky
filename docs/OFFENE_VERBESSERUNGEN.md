# Offene Verbesserungen

Sammlung von Verbesserungen. Offen sind «Später: eigenes UI für die
Korrektur-Optionen» und «Spalte `tasks.locked` entfernen»; alle anderen
Punkte sind umgesetzt.

## Lerneinheiten

### Freigabe und Sperre als ein fortlaufender Status

**Status:** umgesetzt.

Eine Lerneinheit hat heute zwei voneinander unabhängige Zustände:

- freigegeben / nicht freigegeben (`status` in `Tasky.Tasks.Task`)
- gesperrt / nicht gesperrt (`locked` in `Tasky.Tasks.Task`)

Das sollte in einem einzigen Status zusammengeführt werden, der fortlaufend
durchlaufen wird, statt zwei Schalter zu kombinieren.

**Entscheid:** Entwurf → Gesperrt → Offen.

- **Entwurf:** für Lernende unsichtbar.
- **Gesperrt:** sichtbar, aber nicht startbar («Bald verfügbar»).
- **Offen:** bearbeitbar.

Zurückschalten bleibt möglich. Der heute ungenutzte Wert «archiviert» fällt
weg.

### Später: Spalte `tasks.locked` entfernen

Die Migration `MergeTaskReleaseStateIntoStatus` überführt `locked` in den
neuen Status, lässt die Spalte aber stehen: Migrationen laufen beim Start der
neuen Maschine, während die alte Version noch Anfragen beantwortet und
`locked` noch liest. Sobald die neue Version überall läuft, in einem
**separaten, späteren Deploy** die Spalte mit einer eigenen Migration
entfernen.

### Modal «Lerneinheit kopieren»

**Status:** umgesetzt.

Betrifft das Kopier-Modal in `TaskyWeb.CourseLive.Show` (`#copy-task-modal`).

- **Modal ist zu klein.** Es sollte mehr Platz bekommen.
- **Kursbeschreibung fehlt.** Bei der Auswahl der Zielkurse wird nur der
  Kurstitel angezeigt. Oft lässt sich ein Kurs aber erst anhand seiner
  Beschreibung eindeutig erkennen. Die Beschreibung der Zielkurse soll darum
  in der Auswahl mit angezeigt werden.

## Prüfungen

### Korrektur-Optionen je nach Antworttyp

**Status:** umgesetzt.

Beim Erfassen der Musterlösung stehen heute immer dieselben Optionen zur
Verfügung, also auch «Gross-/Kleinschreibung ignorieren» und «Rechtschreibung
ignorieren» (`TaskyWeb.ExamLive.Content`). Bei Checkboxen ergeben diese
Optionen keinen Sinn.

- Die angebotenen Optionen sollen vom Antworttyp abhängen. Textoptionen nur
  dort anzeigen, wo es Textantworten gibt.
- Bei Checkboxen wäre stattdessen eine Option denkbar, **wie korrigiert
  werden soll**.

**Entscheid:** Vorerst kein Korrekturmodus für Checkboxen. Es bleibt bei
«pro Checkbox»: Jede richtig gesetzte bzw. richtig leer gelassene Checkbox
gibt ihren Anteil der Punkte. Für Checkboxen werden also nur die Textoptionen
ausgeblendet.

Hinweis: Die Optionen hängen heute an der Teilaufgabe, nicht am einzelnen
Antwortfeld. Enthält eine Teilaufgabe gemischte Antworttypen, muss geklärt
werden, wo die typabhängigen Optionen leben.

### Option «Satzzeichen ignorieren» für Textantworten

**Status:** umgesetzt.

Neue Korrektur-Option für Textantworten: **Satzzeichen ignorieren**. Ist sie
aktiv, spielt es keine Rolle, ob Punkt, Komma, Ausrufezeichen, Fragezeichen
usw. geschrieben wurden.

- Wirkt wie die anderen Textoptionen in Auto-Korrektur und Sammelkorrektur
  (`Tasky.Correction.StringComparator.text_match?/3`).
- Das `;` trennt in der Musterlösung alternative Antworten. Die Satzzeichen
  werden darum erst nach dem Aufteilen in Alternativen entfernt.
- Wird wie die übrigen Textoptionen bei Checkboxen nicht angezeigt.

### Später: eigenes UI für die Korrektur-Optionen

Mit «Satzzeichen ignorieren» gibt es drei Textoptionen plus «Auto-Korrektur».
Vorerst bleibt das UI, wie es ist. In einem nächsten Schritt prüfen, ob die
Optionen ein kompakteres, übersichtlicheres UI brauchen.

### Checkboxen in der Korrektur als Gruppe darstellen

**Status:** umgesetzt.

In der Korrekturansicht ist bei Checkboxen nicht verständlich, was passiert
ist:

- Ich sehe, dass die Person bei drei Checkboxen Punkte bekommen hat und alles
  grün ist, aber **nicht, ob die Checkbox angekreuzt oder nicht angekreuzt**
  wurde.
- Jede Checkbox erscheint als eigene Frage, obwohl die Checkboxen (anders als
  Textfelder) inhaltlich zusammengehören.

Ziel: Zusammengehörige Checkboxen als eine Gruppe anzeigen, z. B. alle vier
Checkboxen untereinander, und auf einen Blick erkennbar machen:

- was die lernende Person angekreuzt hat,
- was laut Musterlösung richtig ist,
- welche Checkboxen damit richtig bzw. falsch beantwortet sind.

Das ist voraussichtlich eine grössere Änderung.

### «Punkte für eine 6» statt überschriebener Maximalpunkte

**Status:** umgesetzt.

Heute überschreibt die Karte «Maximalpunkte für Benotung» auf der
Benotungskonfiguration die Summe der Musterlösung (`exams.grading_max_points`).
Danach ist die Summe der Musterlösung nirgends mehr sichtbar, und die
«Maximalpunkte» der Tabelle, des PDFs und der Lernenden-Ansicht sind plötzlich
etwas anderes als die Punkte, die man erreichen kann.

Ziel: Es gibt zwei getrennte Zahlen, und man sieht beide.

- **Maximalpunkte** = Summe der Musterlösung. Nicht editierbar, nur Anzeige.
- **Punkte für eine 6** = ab hier gibt es die 6. Editierbar, Standard ist die
  Maximalpunktzahl. Darf darunter liegen, damit auch ohne alle Punkte eine 6
  möglich ist.

**Rechnung bleibt dieselbe.** `Grading.mark/3` teilt schon heute durch einen
Wert und klemmt auf [1, 6]. Dieser Wert heisst nur neu «Punkte für eine 6».
Punkte darüber ergeben weiterhin eine 6.

**Keine Migration.** Die Spalte `grading_max_points` behält Name und Bedeutung;
bestehende Überschreibungen sind bereits «Punkte für eine 6». Eine Umbenennung
der Spalte wäre ein eigener, späterer Deploy (siehe `tasks.locked`).

Schritte:

1. **Domain (`Tasky.Exams`).** `grading_max_points/1` heisst
   `points_for_six/1` (gleiche Logik: Override, sonst Musterlösung). Neu
   `total_points/1` für die Summe der Musterlösung, `nil` bei 0.
   `grading_result/2` liefert zusätzlich `total_points`, `max_points` wird zu
   `points_for_six`. Alle Aufrufer ziehen mit (Grading-Seite, Lernenden-
   Ansicht, beide PDFs, `Paper`).
2. **Karte (`ExamComponents.max_points_card`).** Titel «Punkte für eine 6».
   Darunter eine ruhige Zeile «Maximalpunkte: X (Summe der Musterlösung)».
   Formel-Text anpassen: «Note = (Punkte / Punkte für eine 6) × 5 + 1, höchstens 6.»
   Zurücksetzen-Button setzt auf die Maximalpunkte. Tooltip entsprechend.
   Event-Namen (`set_max_points` usw.) in `grading_config.ex` zu
   `set_points_for_six` umbenennen; Tests mitziehen.
3. **Anzeigen.** Tabelle, Lernenden-Ansicht und PDF zeigen `Punkte / Maximalpunkte`
   (Summe der Musterlösung). Weicht «Punkte für eine 6» ab, steht es klein
   daneben: «6 ab 18». Die Papier-Vorlage (`Paper`, `ExamPaperPdf`) zeigt
   weiterhin die Maximalpunkte.
4. **Freie Dokumente ohne Punkte in der Musterlösung.** Maximalpunkte sind dort
   0 bzw. `nil`; «Punkte für eine 6» ist dann Pflicht, sonst gibt es keine
   Note. Die Karte zeigt den Hinweis statt «Maximalpunkte: –».
5. **Validierung.** Bleibt: grösser als 0. Zusätzlich keine Obergrenze, damit
   ein Wert über den Maximalpunkten (6 praktisch unerreichbar) nicht
   stillschweigend abgelehnt wird; die Karte warnt dann nur.
6. **Tests.** `exam_grading_config_live_test.exs` (Texte, Events, Zurücksetzen),
   `exams_test.exs` (`grading_result`, `total_points`, Note mit Punkten über der
   6-Schwelle bleibt 6.0), `exam_submission_pdf_test.exs`, `pdf_test.exs`.

**Entscheid:** Die Tabelle zeigt «Punkte / Maximalpunkte» pro Zeile und die
6-Schwelle («6 ab X») einmal in der Kopfzeile, nur wenn sie von den
Maximalpunkten abweicht. Die Papier-Vorlage zeigt nur die Maximalpunkte.

### Cockpit: Lernende nach Status filtern

**Status:** umgesetzt.

Im Prüfungs-Cockpit sollen sich die Lernenden nach Status filtern lassen.
Wichtigster Fall: nur noch die Lernenden anzeigen, die **noch in Bearbeitung**
sind.

### Lernende aus einer laufenden oder gestoppten Prüfung entfernen

**Status:** umgesetzt.

Lernende sollen sich auch dann noch aus einer Prüfung entfernen lassen, wenn
die Prüfung bereits **gestartet** oder sogar schon **gestoppt** ist.

Typischer Fall: Die Prüfung ist gestartet, und erst dann stellt sich heraus,
dass eine lernende Person doch nicht kommt. Sie soll dann nachträglich aus der
Prüfung herausgenommen werden können.

**Entscheid:** komplett löschen. Die Person und ihre Abgabe samt Antworten und
Dateien verschwinden aus der Prüfung. Eine laufende Sitzung wird sofort
beendet.

## Allgemein

### Lernende per Namenssuche auswählen

**Status:** umgesetzt.

Beim Auswählen von Lernenden, etwa für eine Prüfung oder einen Kurs, gibt es
heute nur ein Select nach Klasse. Zusätzlich soll es ein **Suchfeld** geben,
über das sich Lernende direkt nach Namen finden lassen.

- Die Suche ignoriert Gross-/Kleinschreibung.
- Das Klassen-Select bleibt bestehen; Suchfeld und Select ergänzen sich.
