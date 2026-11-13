const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../background.js'), 'utf8');
const flush = () => new Promise(resolve => setImmediate(resolve));
async function harness(fetchOverride, bundledToken = 'unit-test-token') {
  const listeners = {}, posts = [], requests = [], session = {};
  const context = {
    SNOOPY_CONFIG: {endpoint: 'http://127.0.0.1:47831', token: bundledToken},
    importScripts() {}, URL, AbortController, Date, Promise, Map, Set, Object, String, Number,
    setTimeout, clearTimeout,
    fetch: async (url, options = {}) => {
      requests.push({url, options});
      if (options.body) posts.push(JSON.parse(options.body));
      return fetchOverride ? fetchOverride(url, options) : {ok: true, status: 200};
    },
    chrome: {
      storage: {
        local: {get: async () => ({}), set: async () => {}},
        session: {get: async () => ({...session}), set: async value => Object.assign(session, value)}
      },
      runtime: {id: 'extension-id', getURL: suffix => 'chrome-extension://extension-id/' + suffix,
        onMessage: {addListener: fn => listeners.message = fn}, onStartup: {addListener: fn => listeners.startup = fn}},
      tabs: {onRemoved: {addListener: fn => listeners.removed = fn}, onUpdated: {addListener: fn => listeners.updated = fn}}
    }
  };
  vm.runInNewContext(source, context);
  await flush();
  return {
    posts, requests, listeners, session,
    send: async (message, sender) => {
      const result = await new Promise(resolve => listeners.message(message, sender, resolve));
      await flush(); return result;
    }
  };
}
const tab = (id = 5) => ({tab: {id, url: 'https://chatgpt.com/c/x'}, url: 'https://chatgpt.com/c/x', frameId: 0, id: 'extension-id'});
const msg = (phase, documentID = 'doc-a') => ({kind: 'snoopy-state', phase, documentID});
test('accepted tab events deliver only phase, source, and pairing token, with no conversation data', async () => {
  const h = await harness();
  assert.equal((await h.send(msg('working'), tab())).ok, true);
  await h.send(msg('done'), tab());
  assert.deepEqual(h.posts, [
    {source: 'chatgpt-tab-5-doc-a', phase: 'working', token: 'unit-test-token'},
    {source: 'chatgpt-tab-5-doc-a', phase: 'done', token: 'unit-test-token'}
  ]);
});
test('rejects forged hosts, subframes, invalid phases, and popup impostors', async () => {
  const h = await harness();
  assert.equal((await h.send(msg('working'), {...tab(), url: 'https://chatgpt.com.attacker.test/'})).ok, false);
  assert.equal((await h.send(msg('working'), {...tab(), frameId: 1})).ok, false);
  assert.equal((await h.send(msg('celebrate'), tab())).ok, false);
  assert.equal((await h.send({kind: 'snoopy-test', phase: 'working'}, tab())).ok, false);
  assert.equal(h.posts.length, 0);
});
test('old document completion cannot end a new document; closing a running tab fails its source', async () => {
  const h = await harness();
  await h.send(msg('working', 'old-doc'), tab());
  await h.send(msg('working', 'new-doc'), tab());
  await h.send(msg('done', 'old-doc'), tab());
  await h.listeners.removed(5); await flush();
  assert.deepEqual(h.posts.map(v => [v.source, v.phase]), [
    ['chatgpt-tab-5-old-doc', 'working'], ['chatgpt-tab-5-old-doc', 'failed'],
    ['chatgpt-tab-5-new-doc', 'working'], ['chatgpt-tab-5-new-doc', 'failed']
  ]);
});
test('a failed start retry is discarded after newer done, so late starts cannot stick', async () => {
  let release;
  let first = true;
  const h = await harness(async (_url, options) => {
    if (options.body && first) {
      first = false;
      await new Promise(resolve => release = resolve);
      throw new Error('offline');
    }
    return {ok: true, status: 200};
  });
  await h.send(msg('working'), tab());
  await h.send(msg('done'), tab());
  release();
  await new Promise(resolve => setTimeout(resolve, 520));
  assert.deepEqual(h.posts.map(v => v.phase), ['working', 'done']);
});
test('popup health is restricted to the extension and test events use an independent source', async () => {
  const h = await harness();
  const popup = {id: 'extension-id', url: 'chrome-extension://extension-id/popup.html'};
  assert.equal((await h.send({kind: 'snoopy-health'}, popup)).connected, true);
  assert.equal(h.requests[0].url, 'http://127.0.0.1:47831/status');
  assert.equal(h.requests[0].options.headers['x-snoopy-token'], 'unit-test-token');
  assert.equal((await h.send({kind: 'snoopy-test', phase: 'working'}, popup)).ok, true);
  assert.equal((await h.send({kind: 'snoopy-test', phase: 'done'}, popup)).ok, true);
  assert.deepEqual(h.posts.map(v => [v.source, v.phase]), [['extension-demo', 'working'], ['extension-demo', 'done']]);
});

test('fresh public extension requires a local pairing token before reporting connected', async () => {
  const h = await harness(undefined, '');
  const popup = {id: 'extension-id', url: 'chrome-extension://extension-id/popup.html'};
  const before = await h.send({kind: 'snoopy-health'}, popup);
  assert.equal(before.connected, false);
  assert.match(before.error, /口令/);
  assert.equal(h.requests.length, 0);
  assert.equal((await h.send({kind: 'snoopy-token', token: '0123456789abcdef'}, popup)).ok, true);
  assert.equal((await h.send({kind: 'snoopy-health'}, popup)).connected, true);
  assert.equal(h.requests[0].options.headers['x-snoopy-token'], '0123456789abcdef');
});

test('SPA URL notifications do not erase fresh work; full document loading interrupts it', async () => {
  const h = await harness();
  await h.send(msg('working'), tab());
  await h.listeners.updated(5, {url: 'https://chatgpt.com/c/new'}); await flush();
  assert.deepEqual(h.posts.map(v => v.phase), ['working']);
  await h.listeners.updated(5, {status: 'loading'}); await flush();
  assert.deepEqual(h.posts.map(v => v.phase), ['working', 'failed']);
  await h.send(msg('working', 'new-document'), tab());
  await h.send(msg('done', 'doc-a'), tab());
  assert.deepEqual(h.posts.map(v => v.phase), ['working', 'failed', 'working']);
});
