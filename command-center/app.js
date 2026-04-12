const OWNER = 'ashish-sadh';
const REPO = 'Drift';
const API = 'https://api.github.com';
// Set this after deploying your Cloudflare Worker
const WORKER_URL = localStorage.getItem('drift_worker_url') || '';
// Set this after registering your GitHub OAuth App
const CLIENT_ID = localStorage.getItem('drift_client_id') || '';

// Auth
function getToken() { return localStorage.getItem('drift_gh_token'); }
function setToken(t) { localStorage.setItem('drift_gh_token', t); }
function clearToken() { localStorage.removeItem('drift_gh_token'); }

function headers() {
  const h = { 'Accept': 'application/vnd.github.v3+json' };
  const t = getToken();
  if (t) h['Authorization'] = `token ${t}`;
  return h;
}

async function api(path, opts = {}) {
  const resp = await fetch(`${API}${path}`, { headers: headers(), ...opts });
  if (resp.status === 401) { clearToken(); showAuth(); throw new Error('Unauthorized'); }
  return resp.json();
}

// OAuth flow
function startOAuth() {
  if (!CLIENT_ID) {
    alert('Configure OAuth: open browser console and run:\nlocalStorage.setItem("drift_client_id", "YOUR_CLIENT_ID")\nlocalStorage.setItem("drift_worker_url", "YOUR_WORKER_URL")');
    return;
  }
  const state = Math.random().toString(36).slice(2);
  localStorage.setItem('drift_oauth_state', state);
  const redirect = `${window.location.origin}${window.location.pathname.replace(/[^/]*$/, '')}callback.html`;
  window.location.href = `https://github.com/login/oauth/authorize?client_id=${CLIENT_ID}&redirect_uri=${encodeURIComponent(redirect)}&scope=repo&state=${state}`;
}

async function exchangeCode(code) {
  if (!WORKER_URL) throw new Error('Worker URL not configured');
  const resp = await fetch(`${WORKER_URL}?code=${code}`);
  const data = await resp.json();
  if (data.access_token) {
    setToken(data.access_token);
    return data;
  }
  throw new Error(data.error_description || 'OAuth exchange failed');
}

async function getUser() {
  try { return await api('/user'); }
  catch { return null; }
}

// Reports
async function listReports() {
  const contents = await api(`/repos/${OWNER}/${REPO}/contents/Docs/reports`);
  return contents
    .filter(f => f.name.endsWith('.md'))
    .sort((a, b) => b.name.localeCompare(a.name));
}

async function getReportContent(path) {
  const data = await api(`/repos/${OWNER}/${REPO}/contents/${path}`);
  return atob(data.content);
}

async function getMetrics() {
  try {
    const data = await api(`/repos/${OWNER}/${REPO}/contents/command-center/metrics.json`);
    return JSON.parse(atob(data.content));
  } catch {
    return null;
  }
}

// PR mapping
async function findPRForReport(filename) {
  // review-cycle-358.md → branch review/cycle-358
  // exec-2026-04-12.md → branch report/exec-2026-04-12
  let branch;
  if (filename.startsWith('review-cycle-')) {
    const cycle = filename.replace('review-cycle-', '').replace('.md', '');
    branch = `review/cycle-${cycle}`;
  } else if (filename.startsWith('exec-')) {
    const date = filename.replace('exec-', '').replace('.md', '');
    branch = `report/exec-${date}`;
  }
  if (!branch) return null;

  const prs = await api(`/repos/${OWNER}/${REPO}/pulls?state=all&head=${OWNER}:${branch}`);
  return prs[0] || null;
}

async function getPRComments(prNumber) {
  return await api(`/repos/${OWNER}/${REPO}/pulls/${prNumber}/comments`);
}

async function submitComment(prNumber, path, line, body) {
  const commitSha = await getLatestCommitOnPR(prNumber);
  return await api(`/repos/${OWNER}/${REPO}/pulls/${prNumber}/comments`, {
    method: 'POST',
    headers: { ...headers(), 'Content-Type': 'application/json' },
    body: JSON.stringify({
      body: `[Human Feedback] ${body}`,
      commit_id: commitSha,
      path: path,
      line: line,
      side: 'RIGHT'
    })
  });
}

async function getLatestCommitOnPR(prNumber) {
  const commits = await api(`/repos/${OWNER}/${REPO}/pulls/${prNumber}/commits`);
  return commits[commits.length - 1].sha;
}

// Markdown rendering (uses marked.js from CDN)
function renderMarkdown(md) {
  if (typeof marked !== 'undefined') return marked.parse(md);
  // Fallback: basic rendering
  return md
    .replace(/^### (.+)$/gm, '<h3>$1</h3>')
    .replace(/^## (.+)$/gm, '<h2>$1</h2>')
    .replace(/^# (.+)$/gm, '<h1>$1</h1>')
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/\n/g, '<br>');
}

// UI helpers
function showAuth() {
  const el = document.getElementById('auth-area');
  if (el) el.innerHTML = `<button class="btn btn-primary" onclick="startOAuth()">Sign in with GitHub</button>`;
}

async function showUser() {
  const user = await getUser();
  const el = document.getElementById('auth-area');
  if (!el) return;
  if (user) {
    el.innerHTML = `
      <div class="user-info">
        <img src="${user.avatar_url}" alt="${user.login}">
        <span>${user.login}</span>
        <button class="btn" onclick="clearToken();location.reload()">Sign out</button>
      </div>`;
  } else {
    showAuth();
  }
}

function formatDate(filename) {
  // Extract date from filename
  const m = filename.match(/(\d{4}-\d{2}-\d{2})/);
  if (m) return m[1];
  const c = filename.match(/cycle-(\d+)/);
  if (c) return `Cycle ${c[1]}`;
  return filename;
}

function reportType(filename) {
  if (filename.startsWith('exec-')) return { label: 'Exec Report', cls: 'type-exec' };
  if (filename.startsWith('review-')) return { label: 'Product Review', cls: 'type-review' };
  return { label: 'Report', cls: '' };
}
