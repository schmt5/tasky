# ISDS-Lückenanalyse learning line (Kanton Bern)

Status: **offen**. Stand der Analyse: 2026-11-03. Sie beruht auf einem Code-Audit von Commit `6962c97` und den ISDS-Vorlagen des KAIO Kanton Bern (Stand 10.07.2025).

Dieses Dokument verfolgt, was learning line braucht, damit wir als Leistungserbringerin den **Grundschutznachweis** nach ICSGW Anhang 2 und 3 liefern können. Dazu gehört auch, was die Schule für ihre ISDS-Unterlagen von uns braucht.

Jedes Finding hat eine ID (A1, B3, C2 …). Die Phasen unten verweisen darauf. Abhaken bitte an beiden Orten: im Finding und in der Phase.

## Grundlagen

**Massgebliche Vorgaben:**

- Weisung ICSGW über den Grundschutz für Informations- und Cybersicherheit mit Anhängen:
  - 1 Schutzniveaus
  - 2 Grundschutz ICT
  - 3 Auftragsdatenbearbeitung
  - 5 Authentisierungsmerkmale
  - 6 Kryptographische Verfahren
- AGB IKT der Digitalen Verwaltung Schweiz (DVS)
- Direktionsverordnung ISDS (DV ISDS)
- Kantonales Datenschutzgesetz (KDSG)

**Annahme: Schutzniveau SN1.** Wir bearbeiten Personendaten: Namen, E-Mails, Klassen, Antworten, Noten und Feedback. Besonders schützenswerte Daten bearbeiten wir nicht. Bei SN1 ist normalerweise keine Vorabkontrolle durch die Datenschutzaufsichtsstelle (DSA) nötig. Die Schule bzw. ihre Informationssicherheitsverantwortliche Person (I-SIVE) muss die Einstufung bestätigen.

**Wer liefert was:**

| Dokument | Wer | Pflicht |
|---|---|---|
| ISDS-Analyse (Vorlage 2) | Schule bzw. Behörde | immer |
| Datenschutzbeurteilung (Vorlage 3) | Schule bzw. Behörde | immer |
| **Grundschutznachweis (Vorlage 4):** Blatt «ICT-Mittel» (A2) und «Datenbearbeitung SN 1» (A3) | **wir** | immer |
| ISDS-Konzept, Risikoanalyse (Vorlagen 5/6) | Schule, wir arbeiten zu | wenn die ISDS-Analyse es verlangt oder Grundschutz-Anforderungen nicht erfüllt sind |
| Anmeldung im Register der Datensammlungen | Schule | bei einer Datensammlung |

Nicht erfüllte Grundschutz-Anforderungen schliessen uns nicht automatisch aus. Sie landen aber als Risiko in der Risikoanalyse, und die Schule muss sie akzeptieren.

**Ist-Zustand in Kürze:**

- Hosting:
  - Fly.io in Frankfurt (`fra`), läuft mit `MIX_ENV=demo`
  - Neon Postgres, AWS eu-central-1
  - Cloudflare R2 mit Region `auto`
- Login nur mit Passwort, ohne 2FA und SSO, ohne Sperre nach Fehlversuchen
- Kein Audit-Log, kein Datenexport, keine Rechtstexte
- Kein E-Mail-Versand (absichtlich)

---

## Findings

### A. Blocker: ohne diese Punkte gibt es keinen Grundschutznachweis

- [ ] **A1: Mindestens zwei Faktoren beim Login übers Internet.** ICSGW A2-4.1.4; Anhang 5 Art. 7 verlangt für Admins immer 2FA.
  - Ist: nur Passwort (`lib/tasky/accounts/user.ex`).
  - Variante a: SSO über einen Identity Provider (IdP), der selbst MFA macht, z. B. edulog oder Entra ID der Schule. OIDC und SAML sind für SN1 zugelassen.
  - Variante b: TOTP oder WebAuthn, mindestens für Lehrpersonen und Admins.
  - Für Schüler:innen ohne 2FA braucht es eine dokumentierte Ausnahme der Behörde (Anhang 5 Art. 16, gilt höchstens ein Jahr) oder ebenfalls SSO.
- [ ] **A2: Passwortkomplexität.** Anhang 5 Art. 10: mindestens 10 Zeichen und 3 von 4 Zeichengruppen; für Admins und Konten mit erweiterten Rechten mindestens 15 Zeichen.
  - Ist: 8–72 Zeichen, keine Komplexitätsregel (`lib/tasky/accounts/user.ex:169-178`).
  - Soll: `validate_password/2` je nach Rolle verschärfen.
- [ ] **A3: Sperre nach 5 Fehlversuchen.** Anhang 5 Art. 14; automatische Entsperrung nach mindestens 30 Minuten ist erlaubt.
  - Ist: weder Rate-Limit noch Sperre auf `POST /users/log-in` (`lib/tasky_web/router.ex:328-339`). `plugs/rate_limit.ex` zählt nur im Speicher und nicht über Instanzen hinweg.
  - Soll: Fehlversuche pro Konto in der DB zählen, plus IP-Rate-Limit.
- [ ] **A4: Eigenes Passwort ändern, keine Wiederverwendung, Wechsel erzwingbar.** Anhang 5 Art. 8 a/c/e.
  - Ist: In den Einstellungen gibt es keine Passwortänderung (`lib/tasky_web/live/user_live/settings.ex`), keine Historie und kein «muss ändern»-Flag.
  - Soll: Passwortänderung mit Sudo-Mode (`Accounts.sudo_mode?/2` existiert, `lib/tasky/accounts.ex:145`, wird aber nirgends genutzt), Passwort-Historie und ein Flag `must_change_password`.
- [ ] **A5: Einmalpasswort bei der Erstanmeldung.** Anhang 5 Art. 12.
  - Ist: Passwörter, die Lehrpersonen oder Admins setzen, bleiben dauerhaft gültig (`lib/tasky/accounts.ex:247, 508`).
  - Soll: Gesetzte Passwörter gelten als Einmalpasswort; beim ersten Login wird ein Wechsel erzwungen (hängt an A4).
- [ ] **A6: Protokollierung sicherheitsrelevanter Ereignisse.** ICSGW A2-4.3.6; A2-4.1.6 e verlangt, dass Admin-Aktionen aufgezeichnet werden.
  - Ist: kein Audit-Log (`lib/tasky_web/seb_guard.ex:280`, `docs/ROBUSTNESS_PLAN.md:44`).
  - Soll: eine Audit-Tabelle, in die nur angehängt wird. Erfasst werden:
    - Logins und Fehlversuche, Sperren
    - Passwort-Resets, E-Mail-Änderungen
    - Rollen- und Organisationswechsel, Admin-Aktionen
    - Notenänderungen und Löschungen

    Dazu gehören festgelegte Leserechte und eine Aufbewahrungsfrist.
- [ ] **A7: Ort der Datenbearbeitung, inkl. Redundanz und Backups.** ICSGW A3-SN1-1.
  - Ist: R2-Region `auto`, keine EU-Jurisdiction (`lib/tasky/storage/r2.ex:25`).
  - Soll: R2-Bucket mit EU-Jurisdiction neu anlegen und die Dateien migrieren. Fly-Region festnageln. Klären, wo die Fly-Logs liegen. Siehe auch C1 zum Hosting in der Schweiz.
- [ ] **A8: Datenexport und Backup ohne unsere Mitwirkung.** ICSGW A3-SN1-14/15.
  - Ist: Es gibt nur den ZIP mit den Korrektur-PDFs (`lib/tasky/exams/export_runner.ex`).
  - Soll: Export pro Organisation als JSON oder CSV mit allen Relationen und Dateien, den die Schule selbst auslösen kann.
- [ ] **A9: Nutzungsbedingungen online, Informationspflicht nach KDSG.** ICSGW A3-SN1-5.
  - Ist: weder Datenschutzerklärung noch Impressum noch Nutzungsbedingungen. Login und Registrierung behaupten trotzdem «DSGVO-konform» (`lib/tasky_web/live/user_live/login.ex:113`, `lib/tasky_web/live/user_live/registration.ex:192`).
  - Soll: Claims entfernen, bis sie belegt sind. Datenschutzerklärung mit Subunternehmen und Datenstandorten publizieren, ebenso Nutzungsbedingungen und Impressum.
- [ ] **A10: Löschung nachweisbar und nicht wiederherstellbar.** ICSGW A2-1.2.5, KDSG.
  - Ist: `delete_student/2` lässt Vor- und Nachname sowie E-Mail auf `exam_submissions` stehen, obwohl der Kommentar von «anonymisiert» spricht (`lib/tasky/accounts.ex:549-578`).
  - Soll: die Personenfelder beim Löschen leeren. Löschkonzept mit Fristen nach Schuljahr. Dokumentieren, wie Löschungen in Neon-PITR-Backups und in R2 wirken.

### B. Wichtig: im Nachweis heikel, meist mit wenig Aufwand behebbar

- [ ] **B1: Erratbarer Klassen-Slug bei der Selbstregistrierung.** ICSGW A2-4.1.1.
  - Ist: `slugify(name)`, z. B. `klasse-5a` (`lib/tasky/classes/class.ex:49-56`). Wer den Slug errät, kann ein Konto in einer fremden Klasse anlegen.
  - Soll: zufälliges, rotierbares Beitritts-Token, wie beim Organisations-Invite.
- [ ] **B2: Stille Kontoübernahme möglich.** ICSGW A2-4.1.2, A2-4.1.6.
  - Ist: Nutzer:innen können ihre E-Mail ohne Bestätigung ändern (`lib/tasky_web/live/user_live/settings.ex:157`). Admins ändern Name, E-Mail und Passwort jedes Kontos, ohne dass eine Spur bleibt.
  - Soll: erneute Anmeldung vor solchen Änderungen, Audit-Log (A6), Admin-Rechte nach Least Privilege.
- [ ] **B3: `update_user_role/2` ohne Autorisierungsprüfung** (`lib/tasky/accounts.ex:345`).
- [ ] **B4: Mandantentrennung belegen.** ICSGW A3-SN1-8. Die Trennung ist rein logisch über `Tasky.Policy` und `organization_scope`.
  - Soll: Trennung dokumentieren.
  - Soll: Tests, die beweisen, dass keine Organisation auf eine andere zugreift.
  - Soll: Admin-Zugriff über alle Organisationen auf benannte Personen beschränken und protokollieren.
- [ ] **B5: `/uploads` ohne Authentisierung.**
  - Ist: geschützt nur durch die UUID im Pfad (`lib/tasky_web/router.ex:182-191`).
  - Zu prüfen: Liegen dort auch Antwortdateien von Schüler:innen? Falls ja, Zugriff an Login und Policy binden oder presigned URLs nutzen.
- [ ] **B6: Request-Logs können Inhalte enthalten.** ICSGW A3-SN1-6 (Randdaten).
  - Ist: Phoenix loggt die Request-Parameter auf `:info`. Antworten und Feedback landen so in den Fly-Logs.
  - Soll: `filter_parameters` erweitern (`content`, `body`, `feedback`, `answer` …). Log-Aufbewahrung festlegen: Die DSA nennt 4–6 Wochen für technische Logs.
- [ ] **B7: Session-Lebensdauer.**
  - Ist: 14 Tage gültig und bei Aktivität ohne Ende, kein Idle-Timeout. Session-Tokens liegen roh in `users_tokens` (`lib/tasky/accounts/user_token.ex:44-47`).
  - Soll: Idle-Timeout von 8–12 h, Tokens gehasht speichern.
- [ ] **B8: SEB-Passwörter im Klartext** (`lib/tasky/exams/exam.ex:20-21`). Für SN1 genügt es, das zu dokumentieren; besser wäre Verschlüsselung auf Feldebene.
- [ ] **B9: Kein Malware-Scan.** ICSGW A2-4.3.5.
  - Ist: Uploads werden nicht gescannt; die Magic-Byte-Prüfung gibt es nur für Bilder (`lib/tasky/uploads.ex:774-794`).
  - Soll: ClamAV oder ein Scan-Dienst, oder das Restrisiko begründen. Die Dateien werden bereits sandboxed ausgeliefert.
- [ ] **B10: Netzwerksicherheit.** ICSGW A3-SN1-12: Firewall, IDS/IPS und WAF oder Zero Trust.
  - Ist: Fly hat keine WAF.
  - Soll: z. B. Cloudflare-Proxy mit WAF und DDoS-Schutz vor der App.
- [ ] **B11: Patches und Schwachstellen.** ICSGW A2-4.3.12/13, A2-4.5.1 c.
  - Ist: sobelow, credo und dialyzer laufen in CI.
  - Soll: `mix hex.audit`, `mix_audit` und `npm audit` in CI, dazu Dependabot oder Renovate.
  - Soll: jährlich ein Pentest bzw. eine Prüfung nach OWASP Top 10 mit Bericht.
- [ ] **B12: Backup und Wiederherstellung.** ICSGW A2-4.3.7/8.
  - Ist: Neon-PITR ist das einzige Backup; R2 hat kein Versioning.
  - Soll: Backups über mehrere Generationen, eine Offline- oder WORM-Kopie gegen Ransomware und protokollierte Restore-Tests.
- [ ] **B13: Betrieb und Verfügbarkeit.** ICSGW A2-4.3.15.
  - Ist: kein Health-Check in `fly.toml`, kein Monitoring, `min_machines_running = 0` (Kaltstart am Prüfungstag).
  - Soll: Health-Check, Uptime-Monitoring und Alarmierung, damit wir Ausfälle sofort melden können.
- [ ] **B14: Trennung der Umgebungen.** ICSGW A2-4.3.4, A2-4.5.3.
  - Ist: Prod läuft als `MIX_ENV=demo`.
  - Soll: eine getrennte produktive Instanz; Prod-Daten nie in Demo oder Test.
- [ ] **B15: Ohne E-Mail-Versand gibt es keinen Self-Service-Reset.** Das ist zulässig, muss aber im Berechtigungskonzept stehen: Resets laufen über Lehrpersonen und Admins.

### C. Organisatorisch und vertraglich

- [ ] **C1: Subunternehmen.** Fly.io, Neon und Cloudflare haben ihren Hauptsitz in den USA; die Daten liegen in der EU.
  - AGB DVS Ziff. 9.1 verlangt die schriftliche Genehmigung durch die Schule.
  - Die ISDS-Analyse verlangt bei US-Anbietern die Prüfung des Swiss-U.S. Data Privacy Framework, eine wiederkehrende Kontrolle und eine Exit-Strategie.
  - A3-SN1-3 verlangt, dass wir Herausgabepflichten an ausländische Behörden offenlegen (CLOUD Act).
  - **Empfehlung:** Hosting in der Schweiz, z. B. cloudscale, Infomaniak oder Exoscale, mit Postgres und S3-kompatiblem Speicher. Das entschärft A7, C1 und A3-SN1-2/3 auf einen Schlag. Vor den ersten produktiven Schulen ist der Wechsel billig, danach wird er ein Projekt.
- [ ] **C2: Vertragswerk.**
  - AGB IKT DVS und Auftragsdatenbearbeitung nach KDSG
  - Gerichtsstand Schweiz (A3-SN1-2)
  - ISDS-Pflichten an die Subunternehmen überbinden (A2-1.3.1)
  - Auditrecht
- [ ] **C3: Informationssicherheitsleitlinie**, jährlich überprüft (A2-1.1.1).
- [ ] **C4: Aufgabentrennung** dokumentieren (A2-1.1.2).
- [ ] **C5: Incident-Prozess** (A2-1.1.3/4): Vorfälle innert **24 h** melden, Schwachstellen innert **48 h**; Kontaktstelle und Erreichbarkeit festlegen.
- [ ] **C6: Konzept für die Betriebskontinuität**, also ICT-Service-Continuity bzw. BCM (A2-1.4.1).
- [ ] **C7: Vertraulichkeitserklärungen und Schulung** des Personals (A2-2.1/2.2).
- [ ] **C8: Technische Dokumentation** (A2-4.3.1): Netzwerk- und Systemarchitektur, Datenflussdiagramm, Schlüsselverwaltung, Change-Prozess, Leistungen der Subunternehmen.
- [ ] **C9: Berechtigungskonzept** mit Rollen, Admin-Liste und jährlichem Review (A2-4.1.2, A2-4.1.6).
- [ ] **C10: Malwareschutzkonzept** (A2-4.3.5).
- [ ] **C11: Backup- und Restore-Konzept** (A2-4.3.7).
- [ ] **C12: Lösch- und Archivierungskonzept** (A2-1.2.5).
- [ ] **C13: Übersicht der Randdaten:** alle Logs und Telemetrie mit Zweck, Zugriff, Ort und Frist (A3-SN1-6).
- [ ] **C14: Wartungsfenster** 30 Arbeitstage im Voraus ankündigen (A2-4.5.5).
- [ ] **C15: Sichere Entwicklung** (A2-4.5.1).
  - Das Repo liegt heute auf einem Personenkonto (`github.com/schmt5/tasky`). Besser: eine Organisation mit 2FA-Pflicht.
  - Branch-Protection und geschützte Deploy-Secrets.
  - Nachvollziehbare Builds, z. B. ein signiertes oder per Digest gepinntes Image.
- [ ] **C16: Grundschutznachweis ausfüllen:** `4_Grundschutznachweis.xlsx`, Blätter «ICT-Mittel» und «Datenbearbeitung SN 1».

### D. Bereits erfüllt (für den Nachweis belegen)

- Passwort-Hashing mit bcrypt; nach Anhang 6 Art. 10 zugelassen.
- Schutz gegen das Ausspähen von Konten durch einen Dummy-Check.
- Passwortfelder sind `redact`.
- Session wird bei Login und Logout erneuert (Schutz gegen Session Fixation); offene LiveView-Verbindungen werden beim Logout getrennt.
- TLS ist erzwungen (`force_ssl` mit HSTS, Fly `force_https`); die Verbindung zur DB nutzt TLS mit Zertifikatsprüfung.
- Strikte Content Security Policy; `/uploads` und `/share` werden sandboxed ausgeliefert; CSRF-Schutz.
- Uploads: Whitelist der Dateiendungen, Grössenlimits, UUID-Dateinamen.
- Rollen und Mandanten laufen zentral über `Tasky.Policy`; ohne passenden Scope gibt es keinen Zugriff.
- Neon und R2 verschlüsseln at rest mit AES-256. Für SN1 genügt das (A3-SN1-11), es muss aber dokumentiert werden.
- Keine Tracker, keine Analytics, keine Google Fonts, keine KI-Drittanbieter mit Daten von Schüler:innen.
- Der Container läuft als `nobody`; sobelow, credo und dialyzer laufen in CI.

---

## Umsetzungsplan

### Phase 0: Klärung mit der Schule und intern

Wichtigste Frage zuerst: der IdP. Er entscheidet über Phase 3.

- [ ] Wer ist Vertragspartnerin: privat, whatwedo oder eine andere Firma? Davon hängen C2–C7 ab. Falls whatwedo eine ISO-27001-Zertifizierung oder bestehende Richtlinien hat, übernehmen wir diese.
- [ ] Wer ist Kundin: eine kantonale Schule (BKD) oder eine Gemeinde mit Volksschule? Wer ist dort die I-SIVE?
- [ ] Schutzniveau SN1 durch die I-SIVE der Schule bestätigen lassen.
- [ ] Gibt es einen IdP, z. B. edulog oder Entra ID der Schule?
- [ ] Hosting entscheiden: Schweiz oder EU (C1).

### Phase 1: Quick Wins im Code (wenige Tage)

- [ ] A9: «DSGVO-konform» entfernen
- [ ] B1: Beitritts-Token für Klassen
- [ ] A2: Passwortregeln nach Rolle
- [ ] A3: Sperre nach 5 Fehlversuchen
- [ ] A4: eigene Passwortänderung, Historie, Flag `must_change_password`
- [ ] A5: Einmalpasswörter bei Passwörtern, die Lehrpersonen oder Admins setzen
- [ ] A10: Personenfelder beim Löschen von Schüler:innen leeren
- [ ] B3: Rechteprüfung in `update_user_role/2`
- [ ] B6: `filter_parameters` erweitern
- [ ] B7: Idle-Timeout, gehashte Session-Tokens
- [ ] B11: `hex.audit`, `mix_audit`, `npm audit` in CI; Dependabot
- [ ] A7: R2 mit EU-Jurisdiction, falls das Hosting in der EU bleibt

### Phase 2: Audit-Log und Admin-Härtung

- [ ] A6: Audit-Tabelle, Events, Ansicht für berechtigte Personen, Aufbewahrungsfrist
- [ ] B2: erneute Anmeldung vor sensiblen Änderungen, E-Mail-Änderung absichern
- [ ] B4: Tests zur Mandantentrennung; Admin-Zugriff über Organisationen beschränken und protokollieren
- [ ] B5: Zugriff auf `/uploads` prüfen und gegebenenfalls absichern

### Phase 3: Starke Authentisierung

- [ ] A1: SSO über den IdP der Schule (bevorzugt), sonst TOTP oder WebAuthn für Lehrpersonen und Admins
- [ ] A1: Lösung für Schüler:innen, entweder über SSO oder mit einer dokumentierten Ausnahme der Behörde

### Phase 4: Daten, Löschung, Backup und Betrieb

- [ ] A8: Export pro Organisation (JSON/CSV und Dateien), Self-Service
- [ ] A10 und C12: Löschkonzept und automatische Löschfristen
- [ ] B12 und C11: Backups über mehrere Generationen, Offline- oder WORM-Kopie, Restore-Test mit Protokoll
- [ ] B13: Health-Check, Monitoring, Alarmierung
- [ ] B14: getrennte Prod-Instanz
- [ ] B9: Malware-Scan oder Begründung des Restrisikos
- [ ] B10: WAF und DDoS-Schutz vorschalten
- [ ] B8: SEB-Passwörter verschlüsseln (optional)

### Phase 5: Hosting und Verträge

- [ ] C1: Hosting-Entscheid umsetzen. Falls Schweiz: migrieren. Sonst DPF-Prüfung, Exit-Strategie und Offenlegung zum CLOUD Act.
- [ ] C2: Vertragswerk mit den AGB DVS und der Auftragsdatenbearbeitung
- [ ] A9: Datenschutzerklärung, Nutzungsbedingungen, Impressum
- [ ] C15: Repo in eine Organisation verschieben, Branch-Protection, nachvollziehbare Builds

### Phase 6: Dokumente und Nachweis

- [ ] C3–C10, C13, C14: Dokumente erstellen
- [ ] B15: Reset-Prozess im Berechtigungskonzept (C9) beschreiben
- [ ] B11: Pentest bzw. OWASP-Prüfung mit Bericht
- [ ] C16: Grundschutznachweis ausfüllen und der Schule übergeben
- [ ] Der Schule zuarbeiten: Architekturskizze, Datenflussdiagramm und Datenkatalog für ihre ISDS-Analyse und Datenschutzbeurteilung

---

## Quellen

- ISDS-Vorlagen KAIO, Stand 10.07.2025: `0_Anleitung`, `1_ISDS-Anforderungen`, `2_ISDS-Analyse`, `3_Datenschutzbeurteilung`, `4_Grundschutznachweis`, `5_ISDS-Konzept`, `6_ISDS-Risikoanalyse und Massnahmen`
- Beilage 1: ICSGW mit Anhängen 1–6 (Version 3.0, 09.07.2025)
- Beilage 2: AGB für IKT-Leistungen, DVS, Ausgabe März 2025
- Beilage 3: DV ISDS
