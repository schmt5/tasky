# Safe Exam Browser: Probelauf vor der echten Prüfung

Diese Anleitung ist **nicht optional**. Der Modus `Erzwingen` darf erst
eingeschaltet werden, wenn Schritt 1–6 auf jeder Rechnerart im Prüfungsraum
sauber durchgelaufen sind.

---

## Was die Prüfung leistet — und was nicht

Der Server prüft neu einen Header, den der Safe Exam Browser mitschickt
(`X-SafeExamBrowser-ConfigKeyHash`). Der erwartete Wert wird aus genau der
Konfiguration abgeleitet, die die Teilnehmenden heruntergeladen haben.

Das hebt die Hürde von **«einen Text im Browser-Kennstring umstellen»** auf
**«den kanonischen Hash von SEB nachbauen und eigene Header einschleusen»**.
Für eine beaufsichtigte Klassenprüfung ist das ein grosser Sprung.

Es ist aber **keine kryptografische Grenze**, und so sollte es auch niemandem
beschrieben werden: die `.seb`-Datei bekommt jede:r Lernende, und der Config Key
ist eine reine Funktion ihres Inhalts — er ist also berechenbar. Echte
kryptografische Grenzen wären der Browser Exam Key (hasht die SEB-Programmdatei
selbst) oder eine schlüsselverschlüsselte Konfiguration mit einem Zertifikat,
das auf den Prüfungsrechnern vorinstalliert ist. Beides braucht eine verwaltete
Geräteumgebung und ist der Ausbaupfad, nicht der jetzige Stand.

**Die Aufsicht im Raum bleibt der wichtigste Teil.**

---

## Die drei Modi

Auf der Konfigurationsseite der Durchführung, unter «Serverseitige Prüfung»:

| Modus | Verhalten |
|---|---|
| **Aus** | Keine Prüfung. Der SEB-Hinweis bleibt ein Hinweis. |
| **Melden** (Standard) | Prüft und zeigt im Cockpit, wer verifiziert ist — **blockiert niemanden**. Damit wird der Probelauf gemacht. |
| **Erzwingen** | Ohne gültigen SEB-Schlüssel kein Zugriff, auch nicht auf Speichern und Abgeben. |

`Melden` ist der Standard, damit das Einschalten von SEB niemals eine Klasse
aussperren kann, bevor die Ableitung bestätigt ist.

---

## Probelauf

1. **Vorbereiten.** Prüfung anlegen, Durchführung eröffnen, «Safe Exam Browser
   aktivieren» ankreuzen, speichern. Der Modus steht dann auf **Melden**. Quit-
   und Admin-Passwort werden dabei automatisch erzeugt.

2. **Starten.** Auf einem echten Prüfungsraum-Rechner die `.seb`-Datei
   herunterladen und öffnen. **Windows und macOS getrennt testen** und die
   genaue SEB-Version notieren — sie entscheidet mit, welche Einstellungen
   überhaupt existieren.

3. **Ablesen.** Im Cockpit erscheinen zwei Zähler: «N verifiziert» und «M ohne
   SEB-Schlüssel». Steht die Person auf **verifiziert**, stimmt die Ableitung
   für diese SEB-Version — weiter zu Schritt 5.

4. **Falls «ohne SEB-Schlüssel».** Auf der Konfigurationsseite steht unter
   «Beobachtete SEB-Schlüssel», was der echte Client tatsächlich geschickt hat.

   * Wird dort **nichts** angezeigt, hat SEB gar keinen Header geschickt. Dann
     ist `sendBrowserExamKey` in dieser Version anders benannt oder der Header
     erreicht uns nicht — **nicht auf Erzwingen schalten**.
   * Wird ein Wert angezeigt, weicht unsere Ableitung ab. Zur Gegenprobe die
     SEB-Einstellungen mit dem **Admin-Passwort** öffnen und den dort
     angezeigten Config Key mit dem abgeleiteten vergleichen. Der beobachtete
     Wert kann mit «Akzeptieren» freigegeben werden — das ist der vorgesehene
     Ausweg und für den Prüfungstag völlig legitim.

5. **Den ganzen Weg durchspielen**, im SEB:
   Seite mitten in der Prüfung neu laden (der Editor muss den Text behalten),
   etwas tippen und auf «Gespeichert» warten, abgeben, «SEB beenden» klicken.
   Falls die Prüfung Beilagen hat: eine herunterladen.

6. **Gegenprobe.** In einem normalen Browser mit auf `SEB` gesetztem
   Kennstring die Prüfungs-URL öffnen. Unter **Erzwingen** muss das abgewiesen
   werden. Genau dieser Fall hat vorher die ganze Prüfung geöffnet.

7. **Umschalten** auf **Erzwingen** — erst jetzt, und nur wenn 3–6 auf jeder
   Plattform im Raum sauber waren.

---

## Wenn es während der Prüfung klemmt

**Symptom:** Teilnehmende sehen «Safe Exam Browser erforderlich», obwohl SEB
läuft. Oder: der Editor meldet, dass die Prüfung nur im Safe Exam Browser läuft.

**Sofortmassnahme:** Im Cockpit unter «Serverseitige Prüfung» der roten Schalter
**«SEB-Zwang 15 Minuten aussetzen»**. Die Prüfung läuft sofort weiter; nach 15
Minuten greift der Zwang von selbst wieder. Danach in Ruhe auf **Melden**
zurückstellen und den beobachteten Schlüssel akzeptieren.

Diesen Handgriff einmal vorher durchspielen — nicht zum ersten Mal, wenn 20
Lernende warten.

---

## Regeln für den Prüfungstag

* **Während einer laufenden Durchführung keine SEB-Einstellung ändern und kein
  Passwort neu erzeugen.** Jede Änderung ändert den Config Key und macht
  **alle** bereits heruntergeladenen `.seb`-Dateien ungültig.
* **Das Admin-Passwort niemals nennen.** Es sperrt das Einstellungsfenster von
  SEB; wer es kennt, kann die Konfiguration einsehen und verändern. Es steht
  auf der Konfigurationsseite hinter «Anzeigen» und wird nur beim Probelauf
  gebraucht.
* **Das Quit-Passwort nur bei Bedarf mündlich weitergeben.** Nach der Abgabe
  beendet sich SEB über den Quit-Link ohnehin von selbst.
* **Beilagen vor dem Eröffnen der Durchführung hochladen.** Ob Downloads im SEB
  erlaubt sind, wird beim Eröffnen festgelegt und danach eingefroren — eine
  später hinzugefügte Beilage wäre im SEB nicht herunterladbar.

---

## Was das Cockpit während der Prüfung zeigt

| Anzeige | Bedeutung |
|---|---|
| **N verifiziert** | So viele Anwesende haben einen gültigen SEB-Schlüssel geschickt. |
| **M ohne SEB-Schlüssel** | So viele nicht. Unter «Melden» schreiben sie trotzdem mit. |
| «SEB noch nicht gestartet» | Anwesend, aber (noch) nicht im SEB. Normal vor dem Start. |
| «SEB nicht verifiziert» | Gibt sich als SEB aus, ohne gültigen Schlüssel. Entweder eine veraltete `.seb`-Datei — oder jemand, der es versucht. Hinschauen. |
