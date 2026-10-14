# Offene Verbesserungen

Sammlung von Verbesserungen, die noch umgesetzt werden sollen.

## Lerneinheiten

### Freigabe und Sperre als ein fortlaufender Status

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

### Modal «Lerneinheit kopieren»

Betrifft das Kopier-Modal in `TaskyWeb.CourseLive.Show` (`#copy-task-modal`).

- **Modal ist zu klein.** Es sollte mehr Platz bekommen.
- **Kursbeschreibung fehlt.** Bei der Auswahl der Zielkurse wird nur der
  Kurstitel angezeigt. Oft lässt sich ein Kurs aber erst anhand seiner
  Beschreibung eindeutig erkennen. Die Beschreibung der Zielkurse soll darum
  in der Auswahl mit angezeigt werden.

## Prüfungen

### Korrektur-Optionen je nach Antworttyp

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

### Cockpit: Lernende nach Status filtern

Im Prüfungs-Cockpit sollen sich die Lernenden nach Status filtern lassen.
Wichtigster Fall: nur noch die Lernenden anzeigen, die **noch in Bearbeitung**
sind.

### Lernende aus einer laufenden oder gestoppten Prüfung entfernen

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

Beim Auswählen von Lernenden, etwa für eine Prüfung oder einen Kurs, gibt es
heute nur ein Select nach Klasse. Zusätzlich soll es ein **Suchfeld** geben,
über das sich Lernende direkt nach Namen finden lassen.

- Die Suche ignoriert Gross-/Kleinschreibung.
- Das Klassen-Select bleibt bestehen; Suchfeld und Select ergänzen sich.
