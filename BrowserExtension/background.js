'use strict';
importScripts('config.js');
const {endpoint, token: bundledToken} = SNOOPY_CONFIG;
const PHASES = new Set(['working', 'done', 'failed']);
const records = new Map();
const latestRevision = new Map();
const queues = new Map();
let configToken = bundledToken;
let connection = {connected: false, error: '尚未连接', checkedAt: 0};
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const ready = (async () => {
  const options = await chrome.storage.local.get('token');
  if (typeof options.token === 'string' && options.token.trim()) configToken = options.token.trim();
  const saved = await chrome.storage.session.get('activeTabs');
  for (const [key, value] of Object.entries(saved.activeTabs || {})) records.set(key, value);
})();

function isChatGPTURL(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && (url.hostname === 'chatgpt.com' || url.hostname === 'chat.openai.com');
  } catch (_) { return false; }
}
function persist() {
  return chrome.storage.session.set({activeTabs: Object.fromEntries(records)});
}
async function request(path, options = {}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 2200);
  try {
    const response = await fetch(endpoint + path, {...options, signal: controller.signal});
    if (!response.ok) throw new Error('HTTP ' + response.status);
    connection = {connected: true, error: '', checkedAt: Date.now()};
    return response;
  } catch (error) {
    connection = {connected: false, error: String(error.message || error), checkedAt: Date.now()};
    throw error;
  } finally { clearTimeout(timeout); }
}
function enqueue(source, phase) {
  const revision = (latestRevision.get(source) || 0) + 1;
  latestRevision.set(source, revision);
  const previous = queues.get(source) || Promise.resolve();
  const next = previous.catch(() => {}).then(async () => {
    for (let attempt = 0; attempt < 2; attempt++) {
      // Never deliver an older start after a later completion/navigation.
      if (latestRevision.get(source) !== revision) return;
      try {
        await request('/event', {
          method: 'POST', headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({source, phase, token: configToken})
        });
        return;
      } catch (_) {
        if (attempt === 0) await delay(450);
      }
    }
  });
  queues.set(source, next);
  next.finally(() => {
    if (queues.get(source) === next) queues.delete(source);
  });
  return next;
}
async function stateFromTab(message, sender) {
  await ready;
  if (!sender.tab || !Number.isInteger(sender.tab.id) || !isChatGPTURL(sender.url || sender.tab.url) ||
      sender.frameId !== 0 || !PHASES.has(message.phase) ||
      typeof message.documentID !== 'string' || !/^[a-zA-Z0-9-]{1,80}$/.test(message.documentID)) return {ok: false};
  const key = String(sender.tab.id);
  const source = 'chatgpt-tab-' + key + '-' + message.documentID;
  const existing = records.get(key);
  if (message.phase === 'working') {
    if (existing && existing.source !== source) enqueue(existing.source, 'failed');
    records.set(key, {source, updatedAt: Date.now()});
    await persist();
    enqueue(source, 'working');
  } else {
    // Completion from an old document cannot alter the new page in the same tab.
    if (existing && existing.source === source) {
      records.delete(key);
      await persist();
      enqueue(source, message.phase);
    }
  }
  return {ok: true};
}
async function popupAction(message, sender) {
  await ready;
  if (sender.tab || sender.id !== chrome.runtime.id || !sender.url || !sender.url.startsWith(chrome.runtime.getURL(''))) return {ok: false};
  if (message.kind === 'snoopy-health') {
    if (!configToken) return {ok: true, connected: false, error: '请先设置连接口令', activeTabs: records.size};
    try { await request('/status', {headers: {'x-snoopy-token': configToken}}); } catch (_) {}
    return {ok: true, ...connection, activeTabs: records.size};
  }
  if (message.kind === 'snoopy-test' && PHASES.has(message.phase)) {
    if (!configToken) return {ok: false, connected: false, error: '请先设置连接口令'};
    await enqueue('extension-demo', message.phase);
    return {ok: connection.connected, ...connection};
  }
  if (message.kind === 'snoopy-token' && typeof message.token === 'string' && /^[a-zA-Z0-9-]{16,128}$/.test(message.token.trim())) {
    configToken = message.token.trim();
    await chrome.storage.local.set({token: configToken});
    return {ok: true};
  }
  return {ok: false};
}
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (!message || typeof message !== 'object') return false;
  const work = message.kind === 'snoopy-state' ? stateFromTab(message, sender) : popupAction(message, sender);
  work.then(respond, () => respond({ok: false, connected: false, error: '连接失败'}));
  return true;
});
chrome.tabs.onRemoved.addListener(async tabID => {
  await ready;
  const key = String(tabID), entry = records.get(key);
  if (entry) {
    records.delete(key);
    await persist();
    enqueue(entry.source, 'failed');
  }
});
chrome.tabs.onUpdated.addListener(async (tabID, change) => {
  // Only a full document load ends the old lease here. SPA URL updates are
  // handled inside that document; a delayed URL notification must not erase
  // a fresh working event from the same ChatGPT page.
  if (change.status !== 'loading') return;
  await ready;
  const key = String(tabID), entry = records.get(key);
  if (entry) {
    records.delete(key);
    await persist();
    enqueue(entry.source, 'failed');
  }
});
chrome.runtime.onStartup.addListener(async () => {
  await ready;
  // After browser restart, prior documents no longer exist. Do not replay success.
  const stale = Array.from(records.values());
  records.clear();
  await persist();
  for (const entry of stale) enqueue(entry.source, 'failed');
});
