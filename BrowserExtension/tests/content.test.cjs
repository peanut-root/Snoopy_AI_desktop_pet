const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../content.js'), 'utf8');
function harness() {
  let now = 10000;
  let buttons = [], streaming = [];
  const messages = [], events = {};
  let poll, mutation;
  const location = {href: 'https://chatgpt.com/c/a', reload() {}};
  const context = {
    Date: {now: () => now}, location,
    crypto: {randomUUID: () => 'doc-a'},
    document: {documentElement: {}, querySelectorAll: selector => selector.includes('data-is-streaming') ? streaming : buttons},
    getComputedStyle: el => ({display: el.display || 'block', visibility: el.visibility || 'visible'}),
    chrome: {runtime: {sendMessage: value => { messages.push(value); return Promise.resolve({ok: true}); }}},
    MutationObserver: class { constructor(fn) {mutation = fn;} observe() {} disconnect() {} },
    setInterval: fn => {poll = fn; return 1;}, clearInterval() {},
    setTimeout: fn => {mutation = fn; return 2;}, clearTimeout() {},
    addEventListener: (name, fn) => events[name] = fn
  };
  vm.runInNewContext(source, context);
  return {
    messages, location,
    buttons: value => buttons = value,
    stream: value => streaming = value,
    tick: delta => {now += delta; poll();},
    event: (name, value = {}) => events[name]?.(value)
  };
}
function button(attributes = {}) {
  return {hidden: false, disabled: false, getAttribute: key => attributes[key] || null, getClientRects: () => [{}]};
}
test('no completion from an idle historical chat; Chinese stop control drives work and debounced completion', () => {
  const h = harness();
  assert.equal(h.messages.length, 0);
  h.buttons([button({'aria-label': '停止生成'})]); h.tick(100);
  assert.equal(h.messages.at(-1).phase, 'working');
  h.tick(2000); assert.equal(h.messages.length, 1);
  h.tick(1000); assert.equal(h.messages.length, 2);
  h.buttons([]); h.tick(1000); h.tick(1000);
  assert.equal(h.messages.at(-1).phase, 'working');
  h.tick(1000); assert.equal(h.messages.at(-1).phase, 'done');
  h.tick(5000); assert.equal(h.messages.length, 3);
});
test('transient stop-button removal does not complete a still-running response', () => {
  const h = harness();
  const stop = button({'data-testid': 'stop-button'});
  h.buttons([stop]); h.tick(100);
  h.buttons([]); h.tick(1000);
  h.buttons([stop]); h.tick(1000);
  h.tick(4000);
  assert.ok(h.messages.every(value => value.phase === 'working'));
});
test('hidden buttons and unrelated stop labels are ignored; streaming state fallback works', () => {
  const h = harness();
  const hidden = button({'aria-label': 'Stop generating'}); hidden.display = 'none';
  h.buttons([hidden, button({'aria-label': 'Stop playback'})]); h.tick(1000);
  assert.equal(h.messages.length, 0);
  h.stream([button()]); h.tick(1000);
  assert.equal(h.messages.at(-1).phase, 'working');
});
test('page close and SPA navigation are interruptions rather than successful completions', () => {
  const h = harness();
  h.buttons([button({'aria-label': 'Stop streaming'})]); h.tick(100);
  h.location.href = 'https://chatgpt.com/c/b'; h.buttons([]); h.tick(1000);
  assert.deepEqual(h.messages.map(value => value.phase), ['working', 'failed']);
  h.buttons([button({'data-testid': 'stop-button'})]); h.tick(1000);
  h.event('pagehide');
  assert.deepEqual(h.messages.map(value => value.phase), ['working', 'failed', 'working', 'failed']);
});

test('a user pressing Stop is an interruption and does not trigger dinner', () => {
  const h = harness();
  const stop = button({'data-testid': 'stop-button'});
  h.buttons([stop]); h.tick(100);
  h.event('click', {isTrusted: true, target: {closest: () => stop}});
  h.tick(1000); h.buttons([]); h.tick(1000); h.tick(3000);
  assert.deepEqual(h.messages.map(value => value.phase), ['working', 'failed']);
  h.buttons([stop]); h.tick(1000);
  assert.equal(h.messages.at(-1).phase, 'working');
});

test('bfcache restoration resumes detection without navigating the user page', () => {
  const h = harness();
  const stop = button({'data-testid': 'stop-button'});
  h.buttons([stop]); h.tick(100);
  h.event('pagehide', {persisted: true});
  h.event('pageshow', {persisted: true});
  assert.deepEqual(h.messages.map(value => value.phase), ['working', 'failed', 'working']);
});
