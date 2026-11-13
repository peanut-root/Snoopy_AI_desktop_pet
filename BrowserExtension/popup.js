'use strict';
async function message(value) {
  try { return await chrome.runtime.sendMessage(value); }
  catch (_) { return {connected: false, error: '扩展尚未就绪，请重新加载'}; }
}
function show(result) {
  const connected = Boolean(result && result.connected);
  document.getElementById('dot').classList.toggle('connected', connected);
  document.getElementById('status').textContent = connected ? '已连接本机桌宠' : '还没连接上桌宠';
  const pairingNeeded = !connected && /口令|403/.test(result?.error || '');
  document.getElementById('detail').textContent = connected
    ? '自动跟随 ChatGPT 网页 · ' + (result.activeTabs || 0) + ' 个生成中的页面'
    : pairingNeeded ? '请从桌宠右键菜单复制网页连接口令，在下方保存' : '请先打开 Snoopy Desktop.app，再点重新检查';
  if (pairingNeeded) document.getElementById('pairing').open = true;
}
async function check() { show(await message({kind: 'snoopy-health'})); }
document.getElementById('refresh').addEventListener('click', check);
for (const phase of ['working', 'done']) {
  document.getElementById(phase).addEventListener('click', async () => {
    show(await message({kind: 'snoopy-test', phase}));
  });
}
document.getElementById('save').addEventListener('click', async () => {
  const result = await message({kind: 'snoopy-token', token: document.getElementById('token').value});
  document.getElementById('saveResult').textContent = result.ok ? '已保存。' : '口令格式不正确。';
  if (result.ok) { document.getElementById('token').value = ''; await check(); }
});
check();
