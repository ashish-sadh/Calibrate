const OWNER = 'ashish-sadh';
const REPO = 'Drift';
const API = 'https://api.github.com';
const WORKER_URL = 'https://drift-command-center-auth.asheesh-sadh.workers.dev';
const CLIENT_ID = 'Ov23liSpSMfDtbMAiMdf';

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
  if (!resp.ok) {
    const err = await resp.json().catch(() => ({}));
    throw new Error(err.message || `API error ${resp.status}`);
  }
  return resp.json();
}

// Public API call (no auth needed for public repos)
async function publicApi(path) {
  const resp = await fetch(`${API}${path}`, {
    headers: { 'Accept': 'application/vnd.github.v3+json' }
  });
  if (!resp.ok) throw new Error(`API error ${resp.status}`);
  return resp.json();
}

// OAuth flow
function startOAuth() {
  const state = Math.random().toString(36).slice(2);
  localStorage.setItem('drift_oauth_state', state);
  const redirect = `${window.location.origin}${window.location.pathname.replace(/[^/]*$/, '')}callback.html`;
  window.location.href = `https://github.com/login/oauth/authorize?client_id=${CLIENT_ID}&redirect_uri=${encodeURIComponent(redirect)}&scope=public_repo&state=${state}`;
}

async function exchangeCode(code) {
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

// Reports (use authenticated API if available, falls back to public)
async function smartApi(path) {
  if (getToken()) return api(path);
  return publicApi(path);
}

async function listReports() {
  const contents = await smartApi(`/repos/${OWNER}/${REPO}/contents/Docs/reports`);
  return contents
    .filter(f => f.name.endsWith('.md'))
    .sort((a, b) => b.name.localeCompare(a.name));
}

async function getReportContent(path) {
  const data = await smartApi(`/repos/${OWNER}/${REPO}/contents/${path}`);
  return atob(data.content);
}

async function getMetrics() {
  try {
    const data = await smartApi(`/repos/${OWNER}/${REPO}/contents/command-center/metrics.json`);
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
  // Get both PR review comments AND issue comments
  const [reviewComments, issueComments] = await Promise.all([
    api(`/repos/${OWNER}/${REPO}/pulls/${prNumber}/comments`),
    api(`/repos/${OWNER}/${REPO}/issues/${prNumber}/comments`)
  ]);

  const all = [];

  // PR review comments — use original_line (file line number), ignore position
  reviewComments.forEach(c => {
    const line = c.original_line || c.line;
    if (line) all.push({ ...c, fileLine: line });
  });

  // Issue comments — parse line number from body "[Line 42]"
  issueComments.forEach(c => {
    const match = c.body.match(/\[Line (\d+)\]/);
    if (match) all.push({ ...c, fileLine: parseInt(match[1]) });
  });

  return all;
}

async function submitComment(prNumber, path, line, body) {
  // Use issue comment with line reference in body — works for any line, not just diff lines
  const lineContext = await getLineContext(path, line);
  const commentBody = `**[Line ${line}]** ${path}\n> ${lineContext}\n\n[Human Feedback] ${body}`;

  return await api(`/repos/${OWNER}/${REPO}/issues/${prNumber}/comments`, {
    method: 'POST',
    headers: { ...headers(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ body: commentBody })
  });
}

async function getLineContext(path, lineNum) {
  try {
    const content = await getReportContent(path);
    const lines = content.split('\n');
    return (lines[lineNum - 1] || '').trim().substring(0, 100);
  } catch {
    return '...';
  }
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
  const el = document.getElementById('auth-area');
  if (!el) return;
  if (!getToken()) { showAuth(); return; }
  try {
    const user = await getUser();
    if (user && user.login) {
      el.innerHTML = `
        <div class="user-info">
          <img src="${user.avatar_url}" alt="${user.login}">
          <span>${user.login}</span>
          <button class="btn" onclick="clearToken();location.reload()">Sign out</button>
        </div>`;
    } else {
      // Token exists but user fetch failed — token may be bad
      clearToken();
      showAuth();
    }
  } catch {
    clearToken();
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
