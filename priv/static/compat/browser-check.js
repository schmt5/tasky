/*
 * Zu-alter-Browser-Warnung. Bewusst NICHT Teil des esbuild-Bundles.
 *
 * Warum eine eigene Datei statt eines Hooks in app.js: app.js ist ein ES-Modul
 * mit --target=es2022. Genau die Engine, vor der hier gewarnt werden soll,
 * parst es gar nicht erst — eine Warnung darin würde nie laufen. Diese Datei
 * ist deshalb handgeschriebenes ES5 in einem klassischen <script>, ohne
 * type="module", und darf nie durch einen Bundler laufen.
 *
 * Warum es das überhaupt braucht: der Prüfungsinhalt ist ein leeres
 * <div phx-hook="ExamSubmissionEditor">, das erst React füllt
 * (TaskyWeb.Guest.ExamLive). Und Tailwind v4 legt das komplette Stylesheet in
 * @layer, das eine Engine ohne Cascade-Layer-Unterstützung samt Inhalt
 * verwirft. Beides zusammen ergibt genau das, was drei Lernende an der
 * SEB-Prüfung gesehen haben: Kopfzeile da, darunter alles weiss, keine
 * Fehlermeldung.
 *
 * Absichtlich wegklickbar. Gleiche Haltung wie beim SEB-Guard
 * (TaskyWeb.SebGuard): ein Fehlalarm von uns darf keine laufende Prüfung
 * beenden. Der Test ist ein echter Feature-Test, kein User-Agent-Sniff, also
 * ist ein Fehlalarm unwahrscheinlich — aber "unwahrscheinlich" ist kein Grund,
 * einer Lehrperson den Ausweg zu nehmen.
 */
(function () {
  "use strict";

  // Die Druckansichten rendert Gotenberg mit einem aktuellen Chrome. Der Test
  // schlüge dort nie an, aber ein Overlay im PDF wäre so teuer, dass sich das
  // explizite Ausschliessen lohnt.
  if (document.getElementById("print-ready-signal")) return;

  function missingFeatures() {
    var missing = [];

    // Ohne ES-Module wird app.js nie ausgeführt: kein LiveView, kein Editor.
    if (!("noModule" in document.createElement("script"))) {
      missing.push("ES-Module");
    }

    // Tailwind v4 verpackt das ganze Stylesheet in @layer. Fehlt die
    // Unterstützung, verwirft der Browser nicht nur einzelne Regeln, sondern
    // alle 274 KB — die Seite ist dann komplett ungestylt.
    if (typeof window.CSSLayerBlockRule === "undefined") {
      missing.push("CSS @layer");
    }

    if (!window.CSS || !window.CSS.supports) {
      missing.push("CSS.supports");
      return missing;
    }

    // ~200 Farbwerte im gebauten CSS sind oklch(), ~240 color-mix().
    if (!window.CSS.supports("color", "oklch(50% 0 0)")) {
      missing.push("oklch()");
    }
    if (!window.CSS.supports("color", "color-mix(in oklab, red, blue)")) {
      missing.push("color-mix()");
    }

    return missing;
  }

  var missing = missingFeatures();
  if (missing.length === 0) return;

  var inSeb = navigator.userAgent.indexOf("SEB") !== -1;

  if (window.console && window.console.error) {
    window.console.error(
      "Browser zu alt für diese Anwendung. Fehlende Features: " +
        missing.join(", ") +
        " | User-Agent: " +
        navigator.userAgent
    );
  }

  function render() {
    if (!document.body) return;

    // Durchgehend Inline-Styles: das Stylesheet ist in genau der Situation,
    // die hier gemeldet wird, mit hoher Wahrscheinlichkeit verworfen worden.
    var overlay = document.createElement("div");
    overlay.setAttribute("role", "alertdialog");
    overlay.setAttribute("aria-labelledby", "browser-check-title");
    overlay.style.cssText =
      "position:fixed;top:0;left:0;right:0;bottom:0;z-index:2147483647;" +
      "background:#fafaf9;overflow:auto;padding:24px;" +
      "font-family:system-ui,-apple-system,'Segoe UI',Roboto,Arial,sans-serif;" +
      "font-size:16px;line-height:1.6;color:#1c1917;";

    var card = document.createElement("div");
    card.style.cssText =
      "max-width:560px;margin:8vh auto;background:#ffffff;border:1px solid #e7e5e4;" +
      "border-radius:14px;padding:32px;";

    var title = document.createElement("h1");
    title.id = "browser-check-title";
    title.style.cssText =
      "margin:0 0 12px;font-size:26px;font-weight:600;line-height:1.2;color:#1c1917;";
    title.appendChild(
      document.createTextNode("Dieser Browser ist zu alt für die Prüfung")
    );
    card.appendChild(title);

    var lead = document.createElement("p");
    lead.style.cssText = "margin:0 0 20px;color:#57534e;";
    lead.appendChild(
      document.createTextNode(
        inSeb
          ? "Die installierte Version des Safe Exam Browsers bringt eine zu " +
              "alte Browser-Engine mit. Die Prüfung würde nur als leere, " +
              "weisse Seite erscheinen."
          : "Dieser Browser kann die Prüfung nicht darstellen. Sie würde nur " +
              "als leere, weisse Seite erscheinen."
      )
    );
    card.appendChild(lead);

    var box = document.createElement("div");
    box.style.cssText =
      "background:#fffbeb;border:1px solid #fde68a;border-radius:10px;" +
      "padding:16px;margin:0 0 20px;";

    var boxTitle = document.createElement("p");
    boxTitle.style.cssText =
      "margin:0 0 8px;font-weight:600;color:#92400e;";
    boxTitle.appendChild(document.createTextNode("Das ist zu tun"));
    box.appendChild(boxTitle);

    var steps = document.createElement("ol");
    steps.style.cssText = "margin:0;padding-left:20px;color:#92400e;";

    var stepTexts = inSeb
      ? [
          "Safe Exam Browser mit dem Beenden-Passwort schliessen.",
          "Die aktuelle Version von safeexambrowser.org installieren.",
          "Die Konfigurationsdatei erneut öffnen und die Prüfung starten.",
          "Die Lehrperson informieren, damit die verlorene Zeit angerechnet wird."
        ]
      : [
          "Den Browser auf die aktuelle Version aktualisieren.",
          "Die Seite danach neu laden.",
          "Die Lehrperson informieren, falls das nicht möglich ist."
        ];

    for (var i = 0; i < stepTexts.length; i++) {
      var li = document.createElement("li");
      li.style.cssText = "margin:0 0 4px;";
      li.appendChild(document.createTextNode(stepTexts[i]));
      steps.appendChild(li);
    }
    box.appendChild(steps);
    card.appendChild(box);

    var reassure = document.createElement("p");
    reassure.style.cssText = "margin:0 0 24px;color:#57534e;";
    reassure.appendChild(
      document.createTextNode(
        "Bereits geschriebene Antworten sind gespeichert und gehen dabei nicht verloren."
      )
    );
    card.appendChild(reassure);

    var details = document.createElement("p");
    details.style.cssText =
      "margin:0 0 20px;padding-top:16px;border-top:1px solid #e7e5e4;" +
      "font-size:13px;color:#a8a29e;word-break:break-word;";
    details.appendChild(
      document.createTextNode(
        "Für die Lehrperson — benötigt wird Chromium 111+ oder Safari 16.4+. " +
          "Nicht unterstützt: " +
          missing.join(", ") +
          ". User-Agent: " +
          navigator.userAgent
      )
    );
    card.appendChild(details);

    var dismiss = document.createElement("button");
    dismiss.type = "button";
    dismiss.style.cssText =
      "background:none;border:0;padding:0;font:inherit;font-size:14px;" +
      "color:#78716c;text-decoration:underline;cursor:pointer;";
    dismiss.appendChild(
      document.createTextNode("Diese Meldung ausblenden und es trotzdem versuchen")
    );
    dismiss.onclick = function () {
      if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
    };
    card.appendChild(dismiss);

    overlay.appendChild(card);
    document.body.appendChild(overlay);
  }

  if (document.body) {
    render();
  } else {
    // Nur als Netz: durch das defer-Attribut steht der Body bereits.
    document.addEventListener("DOMContentLoaded", render);
  }
})();
