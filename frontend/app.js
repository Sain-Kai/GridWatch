const API_BASE = (window.GRIDWATCH_API_BASE || 'http://localhost:8080/api').replace(/\/$/, '');
const NODES = [1];
const POLL_MS = 3000;

const state = {
  readings: new Map(),
  provider: null,
  lastIncident: null,
  connected: false,
};

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

function providerLabel(provider) {
  if (provider === 'nvidia-cloud') return 'NVIDIA NIM';
  if (provider === 'ollama-local') return 'Ollama local';
  return provider || 'Unknown';
}

function stateTone(classification) {
  if (!classification || classification === 'OFFLINE') return 'neutral';
  if (classification === 'NORMAL') return 'normal';
  if (classification === 'THERMAL_WARNING' || classification === 'POSSIBLE_TAMPER') return 'warning';
  if (classification === 'COOLING_FAILURE' || classification === 'CRITICAL_OVERHEAT' || classification === 'TAMPER' || classification === 'SENSOR_FAULT') return 'danger';
  return 'info';
}

function fmt(v, digits = 1) {
  return v === null || v === undefined || Number.isNaN(Number(v)) ? '--' : Number(v).toFixed(digits);
}

function fmtInt(v) {
  return v === null || v === undefined ? '--' : String(v);
}

function formatTime(iso) {
  if (!iso) return '--';
  const d = new Date(iso);
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

function formatAge(ms) {
  if (!ms) return '';
  const mins = Math.max(1, Math.round(ms / 60000));
  return `${mins} min ago`;
}

function setText(id, text) {
  const el = $(id);
  if (el) el.textContent = text;
}

function updateBackendStatus(ok) {
  state.connected = ok;
  const dot = $('backend-dot');
  dot.className = `dot ${ok ? 'live' : 'error'}`;
  setText('backend-status', ok ? 'Backend online' : 'Backend offline');
  setText('system-mode', ok ? 'LIVE / POLLING' : 'DISCONNECTED');
}

function updateHealthRing(nodeId, score) {
  const ring = $(`health-ring-${nodeId}`);
  const value = Number(score);
  if (!ring || !Number.isFinite(value)) return;
  const bounded = Math.max(0, Math.min(100, value));
  const deg = bounded * 3.6;
  const tone = bounded < 50 ? 'var(--danger)' : bounded < 75 ? 'var(--warning)' : 'var(--accent)';
  ring.style.background = `conic-gradient(${tone} ${deg}deg, #232b35 ${deg}deg 360deg)`;
}

function renderSparkline(svg, readings) {
  if (!svg) return;
  const width = 640, height = 120, padX = 8, padY = 12;
  const values = [...readings].reverse().map(r => Number(r.tempC)).filter(Number.isFinite);
  svg.innerHTML = '';
  for (const y of [25, 60, 95]) {
    const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
    line.setAttribute('x1', padX); line.setAttribute('x2', width - padX);
    line.setAttribute('y1', y); line.setAttribute('y2', y); line.setAttribute('class', 'grid');
    svg.appendChild(line);
  }
  if (values.length < 2) return;
  const min = Math.min(...values);
  const max = Math.max(...values);
  const range = Math.max(1, max - min);
  const pts = values.map((v, i) => {
    const x = padX + i * ((width - padX * 2) / (values.length - 1));
    const y = height - padY - ((v - min) / range) * (height - padY * 2);
    return [x, y];
  });
  const poly = pts.map(p => p.join(',')).join(' ');
  const area = document.createElementNS('http://www.w3.org/2000/svg', 'polygon');
  area.setAttribute('points', `${pts[0][0]},${height-padY} ${poly} ${pts[pts.length-1][0]},${height-padY}`);
  area.setAttribute('class', 'area');
  svg.appendChild(area);
  const line = document.createElementNS('http://www.w3.org/2000/svg', 'polyline');
  line.setAttribute('points', poly); line.setAttribute('class', 'line');
  svg.appendChild(line);
  const last = pts[pts.length - 1];
  const point = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
  point.setAttribute('cx', last[0]); point.setAttribute('cy', last[1]); point.setAttribute('r', 4); point.setAttribute('class', 'point');
  svg.appendChild(point);
}

function renderNode(nodeId, readings, liveReading) {
  // Use the dedicated live reading for all status indicators so buffered
  // replay records never cause the badge to show a stale fault state.
  const latest = liveReading || readings[0];
  if (!latest) return;
  state.readings.set(nodeId, readings);

  const classification = latest.classification || 'NORMAL';
  const tone = stateTone(classification);
  const badge = $(`node-badge-${nodeId}`);
  badge.textContent = classification.replaceAll('_', ' ');
  badge.className = `state-badge ${tone}`;

  const liveFlag = latest.buffered ? ' \u27f3 replayed' : '';
  setText(`health-${nodeId}`, fmtInt(latest.healthScore));
  updateHealthRing(nodeId, latest.healthScore);
  setText(`state-${nodeId}`, classification.replaceAll('_', ' ') + liveFlag);
  setText(`buffer-${nodeId}`, latest.buffered ? `Network: outage replay \u00b7 ${formatAge(latest.bufferedAgoMs)}` : 'Network: live link');
  setText(`temp-${nodeId}`, fmt(latest.tempC));
  setText(`rise-${nodeId}`, fmt(latest.tempRiseRate, 2));
  setText(`ambient-${nodeId}`, fmt(latest.ambientC));
  setText(`fan-${nodeId}`, latest.fanDriverEnabled ? (latest.fanVerified ? 'YES' : 'NO') : 'DISABLED');
  setText(`ir1-${nodeId}`, latest.ir1 === 1 ? 'CLEAR' : 'BROKEN');
  setText(`ir2-${nodeId}`, latest.ir2 === 1 ? 'SPIN' : 'STOP');
  setText(`fsr-${nodeId}`, fmtInt(latest.fsrValue));

  setText(`kpi-health-${nodeId}`, latest.healthScore != null ? `${latest.healthScore}/100` : '--');
  setText(`kpi-state-${nodeId}`, classification.replaceAll('_', ' '));

  // Sparkline always uses full 20-reading history (live + buffered for context)
  renderSparkline($(`temp-chart-${nodeId}`), readings);
}


function collectLatestIncident() {
  const all = [];
  for (const [nodeId, readings] of state.readings.entries()) {
    readings.forEach(r => {
      if (r.incidentReport && r.classification && r.classification !== 'NORMAL') all.push({ nodeId, ...r });
    });
  }
  all.sort((a,b) => new Date(b.createdAt) - new Date(a.createdAt));
  return all[0] || null;
}

function renderIncident() {
  const incident = collectLatestIncident();
  if (!incident) {
    setText('incident-provider', '--');
    setText('incident-meta', 'No generated incident report in the recent reading window.');
    $('incident-report').className = 'incident-report empty';
    setText('incident-report', 'Trigger a non-normal classification to generate a grounded incident report.');
    $('incident-evidence').innerHTML = '';
    return;
  }
  state.lastIncident = incident;
  setText('incident-provider', providerLabel(incident.reportProvider));
  setText('incident-meta', `Node ${String(incident.nodeId).padStart(2,'0')} · ${incident.classification.replaceAll('_',' ')} · ${formatTime(incident.createdAt)}${incident.buffered ? ` · buffered ${formatAge(incident.bufferedAgoMs)}` : ''}`);
  const box = $('incident-report');
  box.className = 'incident-report';
  box.textContent = incident.incidentReport;
  $('incident-evidence').innerHTML = [
    `Health ${incident.healthScore}/100`,
    `Temp ${fmt(incident.tempC)}°C`,
    `Rise ${fmt(incident.tempRiseRate, 2)}°C/s`,
    `Fan check ${incident.fanDriverEnabled ? (incident.fanVerified ? 'verified' : 'failed') : 'disabled'}`, 
  ].map(x => `<span class="evidence-chip">${esc(x)}</span>`).join('');
}

function renderTimeline() {
  const items = [];
  for (const [nodeId, readings] of state.readings.entries()) {
    readings.slice(0, 10).forEach(r => items.push({ nodeId, ...r }));
  }
  items.sort((a,b) => new Date(b.createdAt) - new Date(a.createdAt));
  const timeline = $('timeline');
  if (!items.length) {
    timeline.innerHTML = '<div class="empty-state">Waiting for readings…</div>';
    return;
  }
  timeline.innerHTML = items.slice(0, 14).map(r => {
    const c = r.classification || 'NORMAL';
    const tone = stateTone(c);
    const buffered = r.buffered ? ' · replayed after outage' : '';
    return `<div class="timeline-item">
      <div class="time">${esc(formatTime(r.createdAt))}</div>
      <div class="event-main">
        <div class="event-top"><span class="event-node">Node ${String(r.nodeId).padStart(2,'0')}</span><span class="event-state" style="color:${tone === 'danger' ? 'var(--danger)' : tone === 'warning' ? 'var(--warning)' : tone === 'normal' ? 'var(--accent)' : '#9cabb8'}">${esc(c.replaceAll('_',' '))}</span></div>
        <div class="event-detail">${esc(fmt(r.tempC))}°C · health ${esc(r.healthScore)}${esc(buffered)}</div>
      </div>
    </div>`;
  }).join('');
}

async function fetchJson(path, options = {}) {
  const response = await fetch(`${API_BASE}${path}`, { ...options, headers: { 'Content-Type': 'application/json', ...(options.headers || {}) } });
  if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
  return response.json();
}

async function poll() {
  try {
    const [nodeResults, llmStatus] = await Promise.all([
      Promise.all(NODES.map(async nodeId => {
        const [readings, liveReading] = await Promise.all([
          fetchJson(`/readings/node/${nodeId}`),
          fetchJson(`/readings/node/${nodeId}/latest-live`).catch(() => null),
        ]);
        return [nodeId, readings, liveReading];
      })),
      fetchJson('/llm-status')
    ]);
    updateBackendStatus(true);
    nodeResults.forEach(([nodeId, readings, liveReading]) => renderNode(nodeId, readings, liveReading));
    state.provider = llmStatus;
    const provider = llmStatus.lastGenerationProvider === 'nvidia-cloud' ? 'NVIDIA NIM' : llmStatus.lastGenerationProvider === 'ollama-local' ? 'Ollama local' : (llmStatus.nvidiaKeyConfigured ? 'NVIDIA NIM ready' : 'Ollama local');
    setText('kpi-provider', provider);
    setText('kpi-provider-caption', `${llmStatus.mode} · embeddings ${providerLabel(llmStatus.embeddingProvider)} · NVIDIA key ${llmStatus.nvidiaKeyConfigured ? 'configured' : 'not configured'}`);
    const latestStates = NODES.map(id => state.readings.get(id)?.[0]?.classification).filter(Boolean);
    const activeAlerts = latestStates.filter(c => c !== 'NORMAL').length;
    setText('kpi-alerts', String(activeAlerts));
    setText('kpi-alert-caption', activeAlerts === 0 ? 'All latest node states are normal' : `${activeAlerts} node${activeAlerts === 1 ? '' : 's'} require attention`);
    renderIncident();
    renderTimeline();
    setText('last-updated', `Last update: ${new Date().toLocaleTimeString()}`);
  } catch (error) {
    updateBackendStatus(false);
    setText('last-updated', `Backend unreachable · ${API_BASE}`);
  }
}


async function askQuestion(question) {
  const q = question.trim();
  if (!q) return;
  const button = $('ask-btn');
  button.disabled = true;
  button.textContent = 'Thinking…';
  try {
    const result = await fetchJson('/ask', { method: 'POST', body: JSON.stringify({ question: q }) });
    $('answer-box').classList.remove('hidden');
    setText('answer-provider', providerLabel(result.provider));
    setText('answer-text', result.answer || '(empty response)');
  } catch (error) {
    showToast(`AI request failed: ${error.message}`);
  } finally {
    button.disabled = false;
    button.innerHTML = 'Ask GridWatch AI <span>→</span>';
  }
}

function showToast(message) {
  const toast = $('toast');
  toast.textContent = message;
  toast.classList.add('show');
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => toast.classList.remove('show'), 3200);
}

$('ask-btn').addEventListener('click', () => askQuestion($('question').value));
$('question').addEventListener('keydown', (e) => {
  if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') askQuestion($('question').value);
});
document.querySelectorAll('[data-question]').forEach(btn => btn.addEventListener('click', () => { $('question').value = btn.dataset.question; $('question').focus(); }));

poll();
setInterval(poll, POLL_MS);
