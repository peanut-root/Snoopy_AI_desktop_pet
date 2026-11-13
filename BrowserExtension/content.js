(() => {
  'use strict';
  const HEARTBEAT_MS = 3000;
  const DONE_DELAY_MS = 2000;
  const STOP_LABEL = /^(?:stop(?:\s+(?:generating|streaming|responding|generation|response))?|停止(?:生成|响应|回答|回覆|输出)|停止|中止生成)$/i;
  const STOP_SELECTORS = [
    'button[data-testid="stop-button"]',
    'button[data-testid="stop-generating-button"]',
    'button[aria-label]',
    'button[title]',
    'button[data-state="streaming"]'
  ].join(',');
  let active = false;
  let absentSince = null;
  let lastSentAt = 0;
  let stopped = false;
  let cancellationPending = false;
  let scheduled = null;
  let lastURL = location.href;
  // A new document owns a different identity, so stale unloads cannot end its successor.
  const documentID = crypto.randomUUID();

  function visible(element) {
    if (element.hidden || element.getAttribute('aria-hidden') === 'true') return false;
    const style = getComputedStyle(element);
    return style.display !== 'none' && style.visibility !== 'hidden' && element.getClientRects().length > 0;
  }

  function isStopButton(button) {
    if (!button || !visible(button) || button.disabled) return false;
    const testID = button.getAttribute('data-testid') || '';
    const label = (button.getAttribute('aria-label') || button.getAttribute('title') || '').trim();
    return testID === 'stop-button' || testID === 'stop-generating-button' ||
      button.getAttribute('data-state') === 'streaming' || STOP_LABEL.test(label);
  }

  function generating() {
    for (const button of document.querySelectorAll(STOP_SELECTORS)) {
      if (isStopButton(button)) return true;
    }
    // Read only state attributes, never conversation text or message values.
    return Array.from(document.querySelectorAll('[data-is-streaming="true"]')).some(visible);
  }

  function send(phase, now) {
    lastSentAt = now;
    try {
      const result = chrome.runtime.sendMessage({kind: 'snoopy-state', phase, documentID});
      if (result && typeof result.catch === 'function') result.catch(() => {});
    } catch (_) { /* Extension can be reloaded while this tab stays open. */ }
  }

  function check() {
    scheduled = null;
    if (stopped) return;
    const now = Date.now();
    if (location.href !== lastURL) {
      // Do not infer successful completion from navigation away from a running chat.
      if (active) send('failed', now);
      active = false;
      absentSince = null;
      cancellationPending = false;
      lastURL = location.href;
    }
    const currentlyGenerating = generating();
    if (cancellationPending) {
      if (!currentlyGenerating) cancellationPending = false;
      return;
    }
    if (currentlyGenerating) {
      absentSince = null;
      if (!active || now - lastSentAt >= HEARTBEAT_MS) send('working', now);
      active = true;
    } else if (active) {
      if (absentSince === null) absentSince = now;
      if (now - absentSince >= DONE_DELAY_MS) {
        send('done', now);
        active = false;
        absentSince = null;
      }
    }
  }

  function schedule() {
    if (!scheduled) scheduled = setTimeout(check, 120);
  }

  addEventListener('click', event => {
    const button = event.target?.closest?.('button');
    if (event.isTrusted && active && isStopButton(button)) {
      send('failed', Date.now());
      active = false;
      absentSince = null;
      cancellationPending = true;
    }
  }, true);

  const observer = new MutationObserver(schedule);
  observer.observe(document.documentElement, {
    childList: true, subtree: true, attributes: true,
    attributeFilter: ['aria-label', 'title', 'data-testid', 'data-is-streaming', 'data-state', 'hidden', 'style', 'class']
  });
  let timer = setInterval(check, 1000);
  addEventListener('pagehide', () => {
    if (active) send('failed', Date.now());
    active = false;
    stopped = true;
    observer.disconnect();
    clearInterval(timer);
    if (scheduled) clearTimeout(scheduled);
  });
  // Resume a bfcache-restored page without navigating or disturbing a draft.
  addEventListener('pageshow', event => {
    if (!event.persisted) return;
    stopped = false;
    observer.observe(document.documentElement, {
      childList: true, subtree: true, attributes: true,
      attributeFilter: ['aria-label', 'title', 'data-testid', 'data-is-streaming', 'data-state', 'hidden', 'style', 'class']
    });
    timer = setInterval(check, 1000);
    check();
  });
  check();
})();
