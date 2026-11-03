// Run with `mix assets.test`: esbuild bundles this file for Node, `node --test`
// runs it. The autosave engine is the most write-critical code in the app — a
// learner's exam answers go through it — so its failure handling is pinned
// here with fake timers and a stub `save`.

import { test, beforeEach, afterEach, mock } from "node:test";
import assert from "node:assert/strict";

import { createAutosave } from "./autosave";
import { fitsKeepalive } from "./react/api";
import {
  AUTOSAVE_DELAY_MS,
  MAX_RETRIES_AFTER_DESTROY,
  RETRY_DELAYS_MS,
} from "./react/editor/constants";

// Minimal page: the engine only adds and removes listeners on these two.
function fakeTarget() {
  const listeners = {};
  return {
    visibilityState: "visible",
    addEventListener: (type, fn) => (listeners[type] = fn),
    removeEventListener: (type, fn) => {
      if (listeners[type] === fn) delete listeners[type];
    },
    fire: (type, event = {}) => listeners[type]?.(event),
    has: (type) => type in listeners,
  };
}

// Lets the engine's promise chains run between timer ticks. setImmediate is
// not among the mocked APIs.
const settle = () => new Promise((resolve) => setImmediate(resolve));

async function tick(ms) {
  mock.timers.tick(ms);
  await settle();
}

const failure = (status, extra = {}) => Object.assign(new Error(`HTTP ${status}`), { status, ...extra });

// A save stub whose answers are scripted per call; anything unscripted succeeds.
function scriptedSave(...outcomes) {
  const calls = [];
  const save = (payload, opts) => {
    calls.push({ payload, opts });
    const outcome = outcomes.shift();
    return outcome ? Promise.reject(outcome) : Promise.resolve({});
  };
  return { save, calls };
}

function engineWith(save) {
  const statuses = [];
  const engine = createAutosave(save, (status, message) => statuses.push({ status, message }));
  return { engine, statuses };
}

// Whether closing the page would be held up by the browser's warning.
function warnsOnUnload() {
  const event = { defaultPrevented: false, preventDefault: () => (event.defaultPrevented = true) };
  globalThis.window.fire("beforeunload", event);
  return event.defaultPrevented;
}

beforeEach(() => {
  globalThis.document = fakeTarget();
  globalThis.window = fakeTarget();
  mock.timers.enable({ apis: ["setTimeout"] });
});

afterEach(() => {
  mock.timers.reset();
});

test("debounces edits into one save of the latest payload", async () => {
  const { save, calls } = scriptedSave();
  const { engine } = engineWith(save);

  engine.schedule("a");
  await tick(AUTOSAVE_DELAY_MS / 2);
  engine.schedule("b");
  await tick(AUTOSAVE_DELAY_MS);

  assert.deepEqual(
    calls.map((c) => c.payload),
    ["b"],
  );
  assert.equal(engine.hasUnsavedChanges(), false);
});

test("retries a transient failure with backoff and keeps the payload meanwhile", async () => {
  const { save, calls } = scriptedSave(failure(503));
  const { engine } = engineWith(save);

  engine.schedule("doc");
  await tick(AUTOSAVE_DELAY_MS);
  assert.equal(calls.length, 1);
  assert.equal(engine.hasUnsavedChanges(), true);
  assert.equal(warnsOnUnload(), true);

  await tick(RETRY_DELAYS_MS[0]);
  assert.equal(calls.length, 2);
  assert.equal(engine.hasUnsavedChanges(), false);
});

test("an expired session keeps the changes and the unload warning, without retrying", async () => {
  const { save, calls } = scriptedSave(failure(401, { permanent: true }));
  const { engine, statuses } = engineWith(save);

  engine.schedule("doc");
  await tick(AUTOSAVE_DELAY_MS);
  await tick(RETRY_DELAYS_MS.at(-1) * 3);

  assert.equal(calls.length, 1);
  assert.equal(engine.hasUnsavedChanges(), true);
  assert.equal(warnsOnUnload(), true);
  assert.equal(statuses.at(-1).status, "error");
  assert.equal(await engine.flush(), true, "a later successful flush clears it");
});

test("the next edit after a permanent failure tries again", async () => {
  const { save, calls } = scriptedSave(failure(422));
  const { engine } = engineWith(save);

  engine.schedule("too long");
  await tick(AUTOSAVE_DELAY_MS);
  engine.schedule("shorter");
  await tick(AUTOSAVE_DELAY_MS);

  assert.deepEqual(
    calls.map((c) => c.payload),
    ["too long", "shorter"],
  );
  assert.equal(engine.hasUnsavedChanges(), false);
});

test("a handed-in submission drops the changes, since nothing can take them", async () => {
  const { save } = scriptedSave(failure(409));
  const { engine } = engineWith(save);

  engine.schedule("doc");
  await tick(AUTOSAVE_DELAY_MS);

  assert.equal(engine.hasUnsavedChanges(), false);
  assert.equal(warnsOnUnload(), false);
});

test("coming back online retries at once instead of waiting out the backoff", async () => {
  const { save, calls } = scriptedSave(failure(503), failure(503), failure(503));
  const { engine } = engineWith(save);

  engine.schedule("doc");
  await tick(AUTOSAVE_DELAY_MS);
  await tick(RETRY_DELAYS_MS[0]);
  await tick(RETRY_DELAYS_MS[1]);
  assert.equal(calls.length, 3);

  globalThis.window.fire("online");
  await settle();

  assert.equal(calls.length, 4);
  assert.equal(engine.hasUnsavedChanges(), false);
});

test("a destroyed engine gives up after a bounded number of retries", async () => {
  const { save, calls } = scriptedSave(...Array(100).fill(failure(503)));
  const { engine } = engineWith(save);

  engine.schedule("doc");
  engine.destroy();
  await settle();
  assert.equal(calls.length, 1, "destroy flushes what is pending");
  assert.equal(globalThis.window.has("online"), false);

  for (let i = 0; i < 50; i++) await tick(RETRY_DELAYS_MS.at(-1));

  assert.equal(calls.length, 1 + MAX_RETRIES_AFTER_DESTROY);
});

test("an unload flush asks for keepalive", async () => {
  const { save, calls } = scriptedSave();
  const { engine } = engineWith(save);

  engine.schedule("doc");
  globalThis.document.visibilityState = "hidden";
  globalThis.document.fire("visibilitychange");
  await settle();

  assert.deepEqual(calls[0].opts, { keepalive: true });
});

test("keepalive is only used for bodies the browser accepts", () => {
  assert.equal(fitsKeepalive(JSON.stringify({ content: "x".repeat(1000) })), true);
  assert.equal(fitsKeepalive("x".repeat(70 * 1024)), false);
  // Counted in bytes, not characters: umlauts take two.
  assert.equal(fitsKeepalive("ä".repeat(40 * 1024)), false);
  assert.equal(fitsKeepalive(undefined), true);
});
