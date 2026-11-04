import { audioPlay } from "./react/api";

// The player of an audio block (`audio` node), drawn without React: on the
// learner's answer sheet (mounted by ExamAnswersForm from the server's
// placeholder, TaskyWeb.ExamDocHTML) and in the teachers' Tiptap node view
// (react/editor/extensions/audio.ts).
//
// With a limit and a learner (`maxPlays` and `api`), every play is the
// server's call (Tasky.AudioPlays): it counts when it starts, the learner may
// pause but not seek, and the position is reported every few seconds, so a
// reload picks the running play up where it was instead of handing out a new
// one. The file only loads while a play runs — the URL alone gets nothing.
//
// Without a limit, or for the teacher, it is a plain player that can seek.

const PROGRESS_EVERY_MS = 5000;
// `seeking` also fires for our own jumps (resume, the clamp below); anything
// further than this from where playback was is the learner's.
const SEEK_SLACK_S = 1.5;

const ICONS = {
  play: "M5.25 5.653c0-.856.917-1.398 1.667-.986l11.54 6.347a1.125 1.125 0 0 1 0 1.972l-11.54 6.347a1.125 1.125 0 0 1-1.667-.986V5.653Z",
  pause: "M15.75 5.25v13.5m-7.5-13.5v13.5",
  speaker:
    "M19.114 5.636a9 9 0 0 1 0 12.728M16.463 8.288a5.25 5.25 0 0 1 0 7.424M6.75 8.25l4.72-4.72a.75.75 0 0 1 1.28.53v15.88a.75.75 0 0 1-1.28.53l-4.72-4.72H4.51c-.88 0-1.704-.507-1.938-1.354A9.009 9.009 0 0 1 2.25 12c0-.83.112-1.633.322-2.396C2.806 8.756 3.63 8.25 4.51 8.25H6.75Z",
};

function icon(name, filled = false) {
  const ns = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(ns, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("fill", filled ? "currentColor" : "none");
  svg.setAttribute("stroke", "currentColor");
  svg.setAttribute("stroke-width", "1.5");
  svg.setAttribute("aria-hidden", "true");
  svg.classList.add("audio-player__icon");
  const path = document.createElementNS(ns, "path");
  path.setAttribute("stroke-linecap", "round");
  path.setAttribute("stroke-linejoin", "round");
  path.setAttribute("d", ICONS[name]);
  svg.append(path);
  return svg;
}

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

function clock(seconds) {
  if (!Number.isFinite(seconds) || seconds < 0) return "–:––";
  const s = Math.floor(seconds);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

/**
 * Mounts the player into `container` and returns `{ destroy() }`.
 *
 *   title     — shown above the bar
 *   maxPlays  — the limit, or null
 *   state     — `{ started, active, position }` from the server
 *   fileUrl   — where the file loads from
 *   api       — base URL of start/progress/finish; null: no limit applies
 *               (the teacher's views)
 *   disabled  — read-back view: nothing can be started any more
 */
export function mountAudioPlayer(container, opts) {
  const { title, maxPlays = null, fileUrl, api = null, disabled = false } = opts;
  const audioId = opts.audioId;
  const limited = Boolean(maxPlays && api);
  let state = { started: 0, active: false, position: 0, ...(opts.state || {}) };

  const audio = new Audio();
  audio.preload = limited ? "none" : "metadata";

  const root = el("div", "audio-player");
  const playBtn = el("button", "audio-player__play");
  playBtn.type = "button";
  const body = el("div", "audio-player__body");
  const head = el("div", "audio-player__head");
  head.append(icon("speaker"), el("span", "audio-player__title", title || "Audio"));

  // A real range input where seeking is allowed; a plain bar where it is not.
  const bar = limited ? el("div", "audio-player__bar") : el("input", "audio-player__seek");
  const fill = el("div", "audio-player__fill");
  if (limited) {
    bar.setAttribute("role", "progressbar");
    bar.setAttribute("aria-label", "Fortschritt");
    bar.append(fill);
  } else {
    bar.type = "range";
    bar.min = "0";
    bar.max = "1000";
    bar.value = "0";
    bar.setAttribute("aria-label", "Position");
  }

  const meta = el("div", "audio-player__meta");
  const time = el("span", "audio-player__time");
  const plays = el("span", "audio-player__plays");
  meta.append(time, plays);
  body.append(head, bar, meta);

  const confirm = el("div", "audio-player__confirm");
  confirm.hidden = true;
  const confirmText = el("p", "audio-player__confirm-text");
  const confirmGo = el("button", "audio-player__confirm-go", "Starten");
  confirmGo.type = "button";
  const confirmCancel = el("button", "audio-player__confirm-cancel", "Abbrechen");
  confirmCancel.type = "button";
  const confirmActions = el("div", "audio-player__confirm-actions");
  confirmActions.append(confirmCancel, confirmGo);
  confirm.append(confirmText, confirmActions);

  const error = el("p", "audio-player__error");
  error.setAttribute("aria-live", "polite");

  root.append(playBtn, body);
  container.replaceChildren(root, confirm, error);

  let busy = false;
  // Where playback legitimately is: the clamp snaps back here.
  let lastTime = Number(state.position) || 0;
  let reportTimer = null;
  let reloads = 0;
  // Where to seek once the file's metadata is in (resume, reload).
  let pendingSeek = null;
  // Whether the learner wants it playing — an error reload must not start a
  // paused player.
  let wantPlaying = false;
  let destroyed = false;

  const exhausted = () => limited && !state.active && state.started >= maxPlays;

  function render() {
    const playing = !audio.paused && !audio.ended;
    playBtn.replaceChildren(icon(playing ? "pause" : "play", !playing));
    playBtn.setAttribute(
      "aria-label",
      playing ? "Pause" : state.active || audio.currentTime > 0 ? "Weiter abspielen" : "Abspielen",
    );
    playBtn.disabled = busy || (limited && (disabled || exhausted()) && !playing);

    const duration = audio.duration;
    // Until the metadata is in, `currentTime` reads 0 even when resuming.
    const at = !audio.src
      ? limited
        ? Number(state.position) || 0
        : 0
      : audio.readyState > 0
        ? audio.currentTime
        : lastTime;
    const ratio = Number.isFinite(duration) && duration > 0 ? Math.min(1, at / duration) : 0;
    if (limited) {
      fill.style.width = `${ratio * 100}%`;
      bar.setAttribute("aria-valuenow", String(Math.round(ratio * 100)));
    } else if (document.activeElement !== bar) {
      bar.value = String(Math.round(ratio * 1000));
    }
    time.textContent = `${clock(at)} / ${clock(duration)}`;

    root.classList.toggle("audio-player--exhausted", exhausted());
    if (!maxPlays) {
      plays.textContent = "";
    } else if (!api) {
      plays.textContent = `Lernende: höchstens ${maxPlays}× abspielbar`;
    } else if (state.active) {
      plays.textContent = `Durchgang ${state.started} von ${maxPlays}`;
    } else if (exhausted()) {
      plays.textContent = `Alle ${maxPlays} Durchgänge gebraucht`;
    } else {
      const left = maxPlays - state.started;
      plays.textContent = `Noch ${left} von ${maxPlays} ${maxPlays === 1 ? "Durchgang" : "Durchgängen"}`;
    }
  }

  function showError(message) {
    error.textContent = message || "";
  }

  function load(at) {
    lastTime = at || 0;
    pendingSeek = lastTime > 0 ? lastTime : null;
    audio.src = fileUrl;
  }

  async function call(action, body, fetchOpts) {
    const view = await audioPlay(api, audioId, action, body, fetchOpts);
    state = { started: view.started, active: view.active, position: view.position };
    return view;
  }

  // Fire and forget: a progress answer can arrive after the play's finish
  // and would otherwise put back a play the server has already closed.
  function report(keepalive = false) {
    if (!limited || !state.active || !audio.src) return;
    const position = Math.floor(audio.currentTime * 10) / 10;
    audioPlay(api, audioId, "progress", { position }, keepalive ? { keepalive: true } : {}).catch(
      () => {},
    );
  }

  async function startPlay() {
    busy = true;
    showError("");
    render();
    try {
      await call("start");
      load(Number(state.position) || 0);
      wantPlaying = true;
      await audio.play();
    } catch (err) {
      showError(err.message || "Abspielen nicht möglich.");
    } finally {
      busy = false;
      render();
    }
  }

  playBtn.addEventListener("click", () => {
    if (!audio.paused) {
      wantPlaying = false;
      audio.pause();
      return;
    }
    if (!limited) {
      if (!audio.src) load(0);
      wantPlaying = true;
      audio.play().catch((err) => showError(err.message));
      return;
    }
    // Paused within a running play: just carry on.
    if (audio.src && state.active) {
      wantPlaying = true;
      audio.play().catch((err) => showError(err.message));
      return;
    }
    // A play that was running before a reload costs nothing to resume.
    if (state.active) {
      startPlay();
      return;
    }
    confirmText.textContent =
      `Durchgang ${state.started + 1} von ${maxPlays} starten? ` +
      "Du kannst pausieren, aber nicht spulen.";
    confirm.hidden = false;
    confirmGo.focus();
  });

  confirmCancel.addEventListener("click", () => {
    confirm.hidden = true;
    playBtn.focus();
  });

  confirmGo.addEventListener("click", () => {
    confirm.hidden = true;
    startPlay();
  });

  if (!limited) {
    bar.addEventListener("input", () => {
      if (!audio.src) load(0);
      const duration = audio.duration;
      if (Number.isFinite(duration)) audio.currentTime = (Number(bar.value) / 1000) * duration;
    });
  }

  // A fresh load reports 0 before the seek to `pendingSeek` has happened.
  audio.addEventListener("timeupdate", () => {
    if (!audio.seeking && pendingSeek == null) lastTime = audio.currentTime;
    render();
  });

  audio.addEventListener("loadedmetadata", () => {
    if (pendingSeek != null) {
      const at = pendingSeek;
      pendingSeek = null;
      audio.currentTime = at;
    }
  });

  audio.addEventListener("playing", () => (reloads = 0));

  audio.addEventListener("seeking", () => {
    if (limited && Math.abs(audio.currentTime - lastTime) > SEEK_SLACK_S) {
      audio.currentTime = lastTime;
    }
  });

  audio.addEventListener("play", () => {
    render();
    if (limited && !reportTimer) reportTimer = setInterval(() => report(), PROGRESS_EVERY_MS);
  });

  audio.addEventListener("pause", () => {
    clearInterval(reportTimer);
    reportTimer = null;
    if (!audio.ended) report();
    render();
  });

  audio.addEventListener("loadedmetadata", render);

  audio.addEventListener("ended", () => {
    clearInterval(reportTimer);
    reportTimer = null;
    wantPlaying = false;
    if (!limited) {
      render();
      return;
    }
    call("finish")
      .catch(() => {})
      .finally(() => {
        audio.removeAttribute("src");
        audio.load();
        lastTime = 0;
        render();
      });
  });

  // A presigned URL expires after a while; a long pause can outlive it. The
  // gated route hands out a fresh one as long as the play runs.
  audio.addEventListener("error", () => {
    if (destroyed || !audio.getAttribute("src")) return;
    if (limited && state.active && reloads < 2) {
      reloads += 1;
      load(lastTime);
      if (wantPlaying) audio.play().catch(() => {});
      return;
    }
    showError("Die Audiodatei konnte nicht geladen werden.");
    render();
  });

  const onPageHide = () => report(true);
  window.addEventListener("pagehide", onPageHide);

  render();

  return {
    destroy() {
      destroyed = true;
      window.removeEventListener("pagehide", onPageHide);
      clearInterval(reportTimer);
      if (!audio.paused) {
        report(true);
        audio.pause();
      }
      audio.removeAttribute("src");
      audio.load();
    },
  };
}

/** The answer sheet's placeholder (TaskyWeb.ExamDocHTML) turned into a player. */
export function mountAudioField(container) {
  const sheet = container.closest("[data-audio-api], .exam-doc-sheet");
  const apiBase = sheet?.dataset.audioApi || null;
  const fileBase = sheet?.dataset.audioFile || null;
  const audioId = container.dataset.audioId;
  const maxPlays = Number(container.dataset.maxPlays) || null;

  let state;
  try {
    state = JSON.parse(container.dataset.state || "{}");
  } catch {
    state = {};
  }

  // Without the learner's routes it is the teacher's preview: their own file,
  // no limit counted.
  const fileUrl = fileBase ? `${fileBase}/${encodeURIComponent(audioId)}` : container.dataset.src;
  if (!fileUrl) return { destroy() {} };

  return mountAudioPlayer(container, {
    audioId,
    title: container.dataset.title,
    maxPlays,
    state,
    fileUrl,
    api: apiBase,
    disabled: "disabled" in container.dataset,
  });
}
