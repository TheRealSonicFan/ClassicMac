import RFB from './browser/novnc/core/rfb.js';
const api = window.classicmac;
const $ = id => document.getElementById(id);
const model = { powerMacG4: 'Power Mac G4', quadra800: 'Quadra 800', powerMac7500: 'Power Mac 7500' };
const icon = { powerMacG4: 'powermac_g4', quadra800: 'quadra_800', powerMac7500: 'powermac_7500' };
let machines = [], selected, rfb, displayID, displayKey, connectTimer, creating = false, connectionGeneration = 0;
const current = () => machines.find(m => m.id === selected);
function message(text) { $('message-text').textContent = text; if (!$('message').open) $('message').showModal(); }
async function action(fn) { try { await fn(); } catch (error) { message(error.message); } }
$('message-ok').onclick = () => $('message').close();
function connect(m) {
  const generation = ++connectionGeneration;
  clearTimeout(connectTimer);
  if (rfb) { rfb.disconnect(); rfb = null; }
  displayID = m?.running ? m.id : null;
  $('curtain').hidden = false;
  if (!m?.running || !m.display) return;
  const id = m.id;
  rfb = new RFB($('display'), m.display.url, { credentials: { password: m.display.password }, shared: true });
  rfb.scaleViewport = true; rfb.resizeSession = false; rfb.qualityLevel = 8; rfb.compressionLevel = 2;
  rfb.classicInputHelpers = m.classicInputHelpers;
  rfb.addEventListener('connect', () => { if (generation === connectionGeneration && displayID === id) { $('curtain').hidden = true; rfb.focus(); } });
  rfb.addEventListener('disconnect', () => { if (generation === connectionGeneration && displayID === id && current()?.running) connectTimer = setTimeout(() => connect(current()), 1000); });
  rfb.addEventListener('securityfailure', event => message(event.detail.reason || 'The Mac’s display could not be authenticated.'));
}
function render() {
  const list = $('machines'); list.replaceChildren();
  for (const m of machines) {
    const row = document.createElement('button'); row.className = m.id === selected ? 'selected' : '';
    row.setAttribute('role', 'option'); row.setAttribute('aria-selected', String(m.id === selected));
    const image = new Image(32, 32); image.src = `${icon[m.machineFamily]}-32.png`; image.alt = '';
    const text = document.createElement('span'); text.className = 'machine-description';
    const name = document.createElement('strong'); name.textContent = m.name;
    const detail = document.createElement('small'); detail.textContent = m.paused ? 'Paused' : m.running ? 'Running now' : model[m.machineFamily];
    text.append(name, detail); row.append(image, text); row.onclick = () => { selected = m.id; render(); }; list.append(row);
  }
  const m = current();
  $('name').textContent = m?.name ?? 'Your classic Macs, on your PC.';
  $('status').textContent = m?.paused ? 'Paused' : m?.running ? 'Running now' : 'Ready';
  $('details').replaceChildren();
  if (m) for (const [name, value] of [['Model', model[m.machineFamily]], ['Memory', `${m.ramMB} MB`], ['Hard disk', `${m.diskSizeGB ?? '—'} GB`], ['Screen', `${m.width} × ${m.height}`], ['Graphics', m.graphicsCard === 'atiRadeon' ? 'ATI Radeon' : 'Standard'], ['Sharing', m.sharedFolderPath ? 'Turn off sharing in Get Info for Windows' : 'Off']]) {
    const dt = document.createElement('dt'), dd = document.createElement('dd'); dt.textContent = name + ':'; dd.textContent = value; $('details').append(dt, dd);
  }
  for (const id of ['start', 'settings', 'disc', 'reveal']) $(id).disabled = !m || (id !== 'reveal' && m.machineFamily === 'powerMac7500');
  for (const id of ['pause', 'restart', 'stop', 'force', 'fullscreen']) $(id).disabled = !m?.running;
  $('settings').disabled ||= !!m?.running; $('disc').disabled ||= !!m?.running;
  $('start').textContent = m?.paused ? 'Resume Mac' : m?.running ? 'Show Mac' : 'Start Mac';
  $('pause').textContent = m?.paused ? 'Resume' : 'Pause';
  const nextDisplay = m?.running ? `${m.id}:${m.display?.url}` : null;
  if (nextDisplay !== displayKey) { displayKey = nextDisplay; connect(m); }
  $('notice').textContent = m?.running ? 'Use Shut Down from Mac OS before closing ClassicMac. Force Off is for an unresponsive Mac.' : m ? 'Choose Start Mac, or use Media to select an installation CD.' : 'Open a .classic folder from your Mac, or create a new Mac.';
}
api.onState(rows => { machines = rows; selected ??= rows[0]?.id; render(); });
api.onProblem(message);
$('open').onclick = () => action(async () => { const id = await api.open(); if (id) selected = id; machines = await api.state(); render(); });
$('start').onclick = () => action(async () => { const m = current(); if (m?.paused) await api.resume(m.id); else if (!m?.running) await api.start(m.id); else $('display').focus(); });
$('pause').onclick = () => action(() => current().paused ? api.resume(selected) : api.pause(selected));
$('stop').onclick = () => action(() => api.shutdown(selected));
$('restart').onclick = () => action(() => api.restart(selected));
$('force').onclick = () => action(() => api.forceOff(selected));
$('disc').onclick = () => action(() => api.disc(selected));
$('reveal').onclick = () => action(() => api.reveal(selected));
$('fullscreen').onclick = () => action(() => document.fullscreenElement ? document.exitFullscreen() : $('display').requestFullscreen());
$('about').onclick = () => message('ClassicMac 4.0 — Desktop edition\n\nClassic Macintosh emulation with QEMU and the Platinum appearance.\n\nMac icons © The Iconfactory, included with permission. Fonts and appearance shared with RetroBoot.\n\nThis first Windows implementation supports Quadra 800 and Power Mac G4 machines. Copland, host folder sharing and built-in Library downloads are still being ported.');
$('library').onclick = () => message('The Windows Library downloader is still being ported. You can open any Quadra 800 or Power Mac G4 .classic folder copied from ClassicMac for Mac, or create a Mac with your own installation disc.');
function edit(create) {
  creating = create; const form = $('editor').querySelector('form'); form.reset();
  $('editor').className = create ? 'creating' : 'editing'; $('editor-title').textContent = create ? 'New Mac' : 'Get Info';
  const m = create ? { name: 'Mac OS 9' } : current();
  for (const field of form.elements) {
    if (!field.name || !Object.hasOwn(m, field.name)) continue;
    if (field.type === 'checkbox') field.checked = m[field.name]; else field.value = m[field.name];
  }
  if (!create) form.elements.resolution.value = `${m.width}x${m.height}`;
  $('editor').showModal();
}
$('new').onclick = () => edit(true); $('settings').onclick = () => edit(false);
$('editor').querySelector('form').addEventListener('submit', event => {
  if (event.submitter?.value !== 'save') return;
  event.preventDefault();
  action(async () => {
    const form = event.currentTarget, fields = Object.fromEntries(new FormData(form));
    if (creating) { const id = await api.create(fields); if (id) selected = id; }
    else {
      for (const input of form.querySelectorAll('input[type=checkbox]')) fields[input.name] = input.checked;
      for (const key of ['ramMB', 'depth']) fields[key] = Number(fields[key]);
      [fields.width, fields.height] = fields.resolution.split('x').map(Number);
      await api.save(selected, fields);
    }
    $('editor').close(); machines = await api.state(); render();
  });
});
window.classicmacEvidence = () => ({ machines: machines.map(m => ({ id: m.id, running: m.running })), connected: $('curtain').hidden, canvas: !!$('display').querySelector('canvas'), selected });
machines = await api.state(); selected = machines[0]?.id; render();
