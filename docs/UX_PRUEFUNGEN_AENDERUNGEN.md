# UX-Durchgang Prüfungen — was sich geändert hat

Durchgesehen wurde der komplette Prüfungspfad: Übersicht → Prüfung → Durchführung
eröffnen → Cockpit → Korrektur (Einzel- und Sammelkorrektur) → Benotung → Rückgabe,
dazu die Sicht der Teilnehmenden (Einschreibelink, Warteraum, Prüfung schreiben,
zurückgegebene Prüfung).

Zwei Ziele: **ein einheitliches UI** und **keine Bugs**. Unten steht zuerst, was
sich sichtbar verändert hat, danach die gefundenen Fehler, und am Schluss eine
Testliste zum Durchklicken.

---

## 1. Einheitliches UI

### Farben: Prüfungen sehen jetzt aus wie der Rest der App

Die Prüfungsübersicht war die einzige Listenseite in Amber/Orange — Kurse, Klassen
und Katalog sind alle in Sky-Blau. Jetzt sind es alle.

| Wo | Vorher | Jetzt |
|---|---|---|
| Übersicht «Meine Prüfungen» — Eyebrow, Titel, Listen-Icons, Leerzustand | Amber | Sky-Blau |
| «Prüfung erstellen» / «Änderungen speichern» | Amber-Button (der einzige in der ganzen App) | Sky-Button wie überall |

Die Startseiten-Karte «Prüfungen verwalten» bleibt bewusst amber — dort hat jeder
Bereich seine eigene Farbe (Kurse blau, Klassen violett, Prüfungen amber).

### Keine Farbverläufe mehr auf Buttons

Der Prüfungspfad war die einzige Stelle in der App mit Gradient-Buttons (fünf
verschiedene Rezepte). Alle sind jetzt flach, in derselben Farbe wie vorher:

- «Prüfung starten» → flaches Grün
- «Prüfung beenden» → flaches Rot
- «Kopieren» (Einschreibelink) → flaches Amber
- «Zur Benotung», «Prüfung zurückgeben» → flaches Sky-Blau
- «Korrektur starten / fortsetzen» → flaches Grün
- Fortschrittsbalken der Auto-Korrektur und des PDF-Exports → flach

«Prüfung starten» und «Prüfung beenden» waren zusätzlich grösser als der
Nachbar-Button «Konfigurieren» — jetzt sind alle drei gleich hoch.

### Ein Status-Chip statt zwei

Die Übersicht hatte ihre eigenen Statusfarben, die von der Detailseite abwichen
(«Offen» war einmal blau und einmal hellblau, «Beendet» einmal violett und einmal
grau). Beide Seiten benutzen jetzt denselben Chip — inklusive des kleinen Punkts
davor.

### Ein Avatar statt drei

Die Initialen-Kreise gab es im Prüfungspfad in einem blau-violetten Farbverlauf,
sonst überall in der App als schlichter blauer Kreis. Jetzt gibt es eine
gemeinsame Komponente, und der Prüfungspfad sieht aus wie Kursfortschritt und
Benutzerverwaltung.

### Einheitliche Begriffe

| Wo | Vorher | Jetzt |
|---|---|---|
| Korrektur-Tabelle, Spaltentitel | «Schüler/in» | «Teilnehmer:in» |
| Benotungs-Tabelle, Spaltentitel | «Lernende:r» | «Teilnehmer:in» |
| Einzelkorrektur, Button | «Erledigt zurück nehmen» | «Erledigt zurücknehmen» |
| Meldung nach «Alle zuweisen» bei einer Person | «1 Teilnehmende zugewiesen.» | «1 Teilnehmer:in zugewiesen.» |

### Einheitliche Dialoge

- Die «Abbrechen»-Buttons in den Dialogen «Exportieren» und «Zurückgeben» waren
  graue Flächen-Buttons, überall sonst sind sie schlichter Text. Jetzt gleich.
- Die Bestätigungs-Buttons haben jetzt dieselbe Grösse wie in allen anderen
  Dialogen.
- Der Fortschritts-Dialog «PDFs werden erstellt …» war der einzige, der nicht dem
  Dialog-Muster der App folgte. Er sieht jetzt aus wie der Dialog beim Kopieren
  eines Kurses, mit Ladespinner und Zähler.

### Tooltips statt Browser-Tooltips

Die Plus/Minus-Knöpfe in der Benotung und die Fragen-Chips in der Sammelkorrektur
benutzten den grauen Browser-Tooltip (`title`), der eine Sekunde zu spät kommt und
nicht zum Design passt. Jetzt der App-Tooltip. Nebeneffekt: die Knöpfe haben
endlich eine Beschriftung für Screenreader («Note um 0.25 senken» statt «−0.25»).

### Klarere Hierarchie: ein Hauptbutton pro Zeile

- **Prüfungsdetail, Status «Beendet»**: Solange noch Teile offen sind, ist «Zur
  Korrektur» der blaue Hauptbutton. Sobald alles korrigiert ist, wird «Zur
  Benotung» der Hauptbutton und «Zur Korrektur» tritt zurück.
- **Korrekturübersicht**: Gleiches Prinzip — «Korrektur überprüfen» tritt zurück,
  sobald alle Teile erledigt sind, weil dann «Zur Benotung» dran ist.

### Abschluss-Screens wie beim Abschluss einer Lerneinheit

Nach dem Abgeben stand da bisher ein nüchterner Kasten mit kleinem Icon, dem
Abgabezeitpunkt und «Du kannst diese Seite jetzt schliessen.» — eine Sackgasse.
Beim Beenden einer Lerneinheit feiert die App denselben Moment dagegen mit
Emoji, Serif-Headline und einem Weg weiter.

Beide Prüfungs-Endscreens («Prüfung abgegeben» und «Prüfung beendet») benutzen
jetzt dieselbe Komponente wie der Lerneinheit-Abschluss:

| | Vorher | Jetzt |
|---|---|---|
| Bild | kleines Icon im Kästchen | grosses Emoji (zufällig beim Abgeben, 🏁 beim Beenden) |
| Titel | «Prüfung abgegeben» | «Prüfung *abgegeben.*» in Serif, Verb grün hervorgehoben |
| Abgabezeitpunkt | «Abgegeben am 23.08.2026 um 16:31 Uhr.» | entfällt — steht weiter im Cockpit der Lehrperson |
| «Seite jetzt schliessen» | ja | entfällt |
| Weiter | nichts (ausser «SEB beenden» im Safe Exam Browser) | Button «Zur Startseite» für angemeldete Teilnehmende |

Der Button erscheint nur, wenn die Teilnehmerin angemeldet ist — ein anonymer
Gast hat in der App keine Startseite, auf die er zurückkehren könnte. Im Safe
Exam Browser bleibt «SEB beenden» der einzige Ausgang.

### Kleinere Aufräumarbeiten

- **Cockpit**: Der Button «Konfigurieren» erscheint nicht mehr, wenn die Prüfung
  schon beendet oder archiviert ist — dort gibt es nichts mehr zu konfigurieren.
- **Prüfung schreiben (Teilnehmende)**: In der Werkzeugleiste war die Gruppe
  «Frage» sichtbar — das ist das Autorenwerkzeug der Lehrperson zum Anlegen einer
  Frage. Auf einem gesperrten Prüfungsdokument bringt es nichts oder macht die
  eigene Antwort zur Überschrift. Ist entfernt; Formatierung (fett, kursiv,
  Listen, Farbe) bleibt.

---

## 2. Behobene Fehler

**«Korrektur fortsetzen» sprang zurück auf Frage 1.**
Der Button verlinkte immer die erste Frage, unabhängig davon, wie weit man war. Bei
einer Prüfung mit acht Fragen und sechs erledigten landete man wieder am Anfang.
Jetzt springt er auf die erste Frage, die noch offen ist.

**«Kopieren» beim Einschreibelink gab überhaupt keine Rückmeldung.**
Zwei Fehler übereinander: Das Skript beschriftete das Icon statt des Textes (also
blieb «Kopieren» stehen), und es tauschte Farbklassen, die der Button gar nicht
hatte. Man wusste nie, ob der Link im Zwischenspeicher war. Jetzt wird der Button
kurz grün und zeigt «Kopiert!». Falls der Browser das Kopieren verweigert (kein
HTTPS, Berechtigung fehlt), wird das Feld markiert und es steht «Bitte manuell
kopieren» — vorher passierte in diesem Fall gar nichts.

**Der Teilnehmerzähler im Cockpit blieb stehen.**
Bei anonymer Durchführung erschienen neu eingeschriebene Personen in der Liste,
aber der Zähler oben rechts blieb auf dem Wert von beim Seitenaufruf. Zähler und
Liste laufen jetzt synchron.

**Die Warnung beim Start der Prüfung war falsch.**
Dort stand: «Nach dem Start können sich keine weiteren Lernenden mehr
einschreiben.» Das stimmt nicht — der Einschreibelink funktioniert auch während der
laufenden Prüfung, und wer sich dann anmeldet, landet direkt in der Prüfung. Der
Text sagt jetzt, was tatsächlich passiert.

**Im Cockpit stand «Im Warteraum», während die Prüfung längst lief.**
Die Anwesenheitsanzeige unterscheidet jetzt: «Im Warteraum» vor dem Start, «In
Bearbeitung» während der Prüfung, «Online» bei jemandem, der schon abgegeben hat.

**Die Zusammenfassung der Sammelkorrektur zählte falsch.**
Manuell vergebene Punkte landeten immer im Balken «Manuell» — auch dann, wenn man
manuell die volle Punktzahl oder 0 vergeben hatte. Die Zusammenfassung widersprach
damit den Punkten und den Markierungen (🟢/🟡/🔴) im Dokument. Jetzt zählt
«manuell = volle Punktzahl» als volle Punkte und «manuell = 0» als 0 Punkte.

**Abstürzen konnte die Personenliste bei fehlendem Namen.**
Die Initialen-Kreise im Cockpit, in der Korrektur und in der Benotung schnitten
den ersten Buchstaben direkt aus dem Vor- und Nachnamen. Fehlte einer davon, warf
die Seite einen Fehler. Die neue gemeinsame Komponente kommt damit zurecht (zeigt
«?»).

**Fehlende Leerzustände in der Korrektur.**
Gab es Fragen, aber noch keine Abgaben, zeigte die Korrekturübersicht eine leere
Tabelle mit Spaltenköpfen und sonst nichts. Jetzt steht dort «Keine Teilnehmenden
vorhanden.», wie in der Benotung.

**Die Status-Chips der Lernenden waren nicht unterscheidbar.**
In «Meine Prüfungen» (Lernendensicht) hatten «Zugewiesen» und «Zurückgegeben»
dieselbe blaue Farbe. Zusätzlich hingen Farbe, Text und Hinweis an drei getrennten
Stellen am deutschen Text — eine Umformulierung hätte still die Farben verloren.
Die Zustände haben jetzt je eine eigene Farbe, abgestimmt auf die Lehrpersonen-
Seite:

| Zustand | Farbe |
|---|---|
| Zugewiesen (noch nicht gestartet) | Amber, wie der Warteraum |
| Läuft | Grün, wie «Laufend» im Cockpit |
| Abgegeben | Violett, wie der «Abgegeben»-Chip im Cockpit |
| Zurückgegeben | Blau, wie «Zurückgegeben am …» in der Benotung |
| Beendet | Grau |

**Roter Build.** `mix precommit` scheiterte schon vorher an drei Dialyzer-Meldungen
(fehlende Typangaben an den Prüfungs-Schemas). Behoben — `mix precommit` läuft jetzt
komplett grün durch (Format, Credo, Sobelow, Dialyzer, 664 Tests).

---

## 3. Was ich testen würde

### Lehrperson

1. **Übersicht** `/exams` — alles blau statt amber? Status-Chips bei Entwurf /
   Offen / Laufend / Beendet plausibel?
2. **Umbenennen** — der Speichern-Button ist jetzt blau statt amber.
3. **Durchführung eröffnen** (Entwurf → «Durchführung öffnen»), einmal mit
   «Lernende zuweisen», einmal mit «Einschreibelink teilen».
4. **Cockpit, anonym**: Auf «Kopieren» klicken → Button wird kurz grün und sagt
   «Kopiert!», danach wieder amber. Link in einem anderen Fenster öffnen, jemanden
   einschreiben → **Zähler oben rechts muss mitzählen**, nicht nur die Liste.
5. **Cockpit, Anwesenheit**: Teilnehmerfenster offen lassen. Vor dem Start muss
   «Im Warteraum» stehen, nach «Prüfung starten» «In Bearbeitung», nach der Abgabe
   «Online» + Chip «Abgegeben».
6. **Prüfung starten**: Text im Bestätigungsdialog lesen — bei anonymer
   Durchführung darf dort **nicht** mehr stehen, dass sich niemand mehr
   einschreiben kann.
7. **Cockpit, zugewiesen**: Klasse filtern → «Alle zuweisen». Bei genau einer
   Person muss die Meldung «1 Teilnehmer:in zugewiesen.» lauten.
8. **Cockpit einer beendeten Prüfung**: «Konfigurieren» ist weg, «Zur Korrektur»
   ist da.
9. **Korrekturübersicht**: Erst 1–2 Teile korrigieren, zurück zur Übersicht →
   **«Korrektur fortsetzen» muss auf den nächsten offenen Teil springen**, nicht
   auf Frage 1. Wenn alles erledigt ist, wird der Button hell und «Zur Benotung»
   oben rechts ist der blaue Hauptbutton.
10. **Sammelkorrektur**: Bei einer Antwortgruppe «Manuell» wählen und die **volle**
    Punktzahl eintragen → die Gruppe muss im Balken bei «Volle Punkte» zählen,
    nicht bei «Manuell». Dasselbe mit 0 → «0 Punkte». Mit einem Zwischenwert →
    «Manuell».
11. **Einzelkorrektur**: Button heisst «Erledigt zurücknehmen». Power-Ansicht
    öffnen, mit J/K/L bewerten, «Zum nächsten Teilnehmenden».
12. **Benotung**: Plus/Minus bei Maximalpunkten und bei der Note — die Tooltips
    sind jetzt die der App und sagen, was passiert. Dialog «Exportieren» öffnen →
    «Abbrechen» ist jetzt Text, nicht grauer Block. Export starten → der
    Fortschritts-Dialog sieht aus wie die anderen Dialoge.
13. **Zurückgeben**: Dialog «Prüfung zurückgeben», danach «Rückgabe zurückziehen».

### Teilnehmende

14. **Einschreibelink** öffnen, anmelden → Warteraum. Lehrperson startet → die
    Seite muss von selbst in die Prüfung wechseln.
15. **Prüfung schreiben**: In der Werkzeugleiste darf **keine Gruppe «Frage»** mehr
    stehen. Fett/kursiv/Listen in einem Antwortfeld müssen weiter funktionieren.
    Antworten tippen, Tab «Dateien», Datei hochladen, «Abgeben».
16. **Angemeldete Lernende** `/student/exams`: Die Chips müssen sich farblich
    unterscheiden — am besten mit je einer Prüfung in «Zugewiesen» (amber),
    «Läuft» (grün), «Abgegeben» (violett) und «Zurückgegeben» (blau).
17. **Zurückgegebene Prüfung** ansehen (`Prüfung ansehen`) — Punkte, Note, Inhalt
    und Musterlösung je nach dem, was beim Zurückgeben angehakt war.
18. **Nach dem Abgeben**: Emoji-Screen «Prüfung *abgegeben.*» ohne Abgabezeitpunkt.
    Angemeldet muss ein Button «Zur Startseite» dastehen und auf `/` führen; über
    einen anonymen Einschreibelink darf er fehlen. Danach die Prüfung als
    Lehrperson beenden — derselbe Screen mit 🏁 und «Prüfung *beendet.*».

### Nebenwirkungen, auf die ich schauen würde

Die gemeinsame Avatar-Komponente und der gemeinsame Status-Chip werden auch
ausserhalb des Prüfungspfads verwendet. Ein kurzer Blick auf **Kursfortschritt**,
**Klassenliste** und **Benutzerverwaltung** schadet nicht — dort sollte sich
nichts verändert haben.

---

## 4. Was ich bewusst nicht angefasst habe

- **«Abgegeben am …»** auf dem Abgabe-Bildschirm der Teilnehmenden zeigt den
  Zeitpunkt der letzten Änderung an der Abgabe, nicht den der Abgabe selbst.
  Läuft die Auto-Korrektur noch während der Prüfung, kann die Uhrzeit später sein
  als die echte Abgabe. Sauber lösen würde eine eigene Spalte `submitted_at`
  heissen — das ist eine Datenbank-Änderung und gehört nicht in einen UX-Durchgang.
- **Überschriften H1/H2 in der Werkzeugleiste der Teilnehmenden.** Ob Lernende ihre
  Antworten mit Überschriften gliedern dürfen, ist eine didaktische Entscheidung,
  keine technische — sag Bescheid, wenn die auch weg sollen.
- **Die Grössenskala der Lernendenseiten** (36 px Titel) weicht von den
  Lehrpersonenseiten (42 px) ab. Das ist innerhalb der Lernendensicht aber
  durchgehend konsistent, also gewollt.
