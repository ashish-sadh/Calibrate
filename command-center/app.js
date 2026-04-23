const OWNER = 'ashish-sadh';
const REPO = 'Drift';
const API = 'https://api.github.com';
const WORKER_URL = 'https://drift-command-center-auth.asheesh-sadh.workers.dev';
const CLIENT_ID = 'Ov23liSpSMfDtbMAiMdf';

// Current user state
let currentUser = null;
let _resolveUserReady;
const userReady = new Promise(r => { _resolveUserReady = r; });
const ADMINS = [OWNER, 'nimisha-26', 'rajatsadh24', 'nehasadh-github', 'arunsadh'];
function isOwner() { return currentUser && ADMINS.includes(currentUser.login); }

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
  // public_repo = minimum scope for commenting on PRs, filing issues on public repos
  window.location.href = `https://github.com/login/oauth/authorize?client_id=${CLIENT_ID}&redirect_uri=${encodeURIComponent(redirect)}&scope=public_repo&state=${state}`;
}

async function exchangeCode(code) {
  const resp = await fetch(`${WORKER_URL}?code=${code}`);
  // GitHub sometimes returns HTML (reused / expired code, redirect URI
  // mismatch) and the worker forwards it verbatim — parsing that as JSON
  // blows up with "unexpected character at line 1 column 1". Read as
  // text first, then try to parse, so we can surface a readable error.
  const raw = await resp.text();
  let data;
  try {
    data = JSON.parse(raw);
  } catch {
    throw new Error(
      resp.status >= 400
        ? `Sign-in rejected by GitHub (${resp.status}). The authorization code may have already been used — go back and start sign-in again.`
        : 'GitHub returned an unexpected response. Try signing in again from the main page.'
    );
  }
  if (data.access_token) {
    setToken(data.access_token);
    return data;
  }
  throw new Error(data.error_description || data.error || 'OAuth exchange failed');
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
  const [prs, contents] = await Promise.all([
    smartApi(`/repos/${OWNER}/${REPO}/issues?labels=report&state=closed&sort=created&direction=desc&per_page=100`),
    smartApi(`/repos/${OWNER}/${REPO}/contents/Docs/reports`)
  ]);

  const fileSet = new Set(contents.filter(f => f.name.endsWith('.md')).map(f => f.name));
  const fileByName = Object.fromEntries(contents.filter(f => f.name.endsWith('.md')).map(f => [f.name, f]));

  function titleToFilename(title) {
    const reviewMatch = title.match(/^(review-cycle-\d+)/i);
    if (reviewMatch) return `${reviewMatch[1].toLowerCase()}.md`;
    const dateMatch = title.match(/(\d{4}-\d{2}-\d{2})/);
    if (dateMatch) return `exec-${dateMatch[1]}.md`;
    return null;
  }

  const seen = new Set();
  const result = [];

  for (const pr of prs) {
    if (!pr.pull_request) continue;
    const filename = titleToFilename(pr.title);
    if (filename && fileSet.has(filename) && !seen.has(filename)) {
      seen.add(filename);
      result.push({ ...fileByName[filename], _date: pr.created_at });
    }
  }

  // Files not covered by a PR — derive date from filename where possible
  const remaining = contents
    .filter(f => f.name.endsWith('.md') && !seen.has(f.name))
    .map(f => {
      const dateMatch = f.name.match(/(\d{4}-\d{2}-\d{2})/);
      return { ...f, _date: dateMatch ? `${dateMatch[1]}T00:00:00Z` : null };
    });

  // Sort combined list newest-first; cycle-only files (no date) fall to bottom by cycle desc
  const combined = [...result, ...remaining];
  combined.sort((a, b) => {
    if (a._date && b._date) return b._date.localeCompare(a._date);
    if (a._date) return -1;
    if (b._date) return 1;
    const numA = a.name.match(/cycle-(\d+)/)?.[1];
    const numB = b.name.match(/cycle-(\d+)/)?.[1];
    if (numA && numB) return parseInt(numB) - parseInt(numA);
    return b.name.localeCompare(a.name);
  });
  return combined;
}

async function getReportContent(path) {
  const data = await smartApi(`/repos/${OWNER}/${REPO}/contents/${path}`);
  // Proper UTF-8 decoding (atob mangles unicode like em-dashes)
  const bytes = Uint8Array.from(atob(data.content), c => c.charCodeAt(0));
  return new TextDecoder('utf-8').decode(bytes);
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
  // review-cycle-358.md → try multiple branch patterns (naming was inconsistent historically)
  // exec-2026-04-12.md → branch report/exec-2026-04-12
  let branches;
  if (filename.startsWith('review-cycle-')) {
    const cycle = filename.replace('review-cycle-', '').replace('.md', '');
    branches = [
      `review/cycle-${cycle}`,
      `review-cycle-${cycle}`,
      `report/review-cycle-${cycle}`
    ];
  } else if (filename.startsWith('exec-')) {
    const date = filename.replace('exec-', '').replace('.md', '');
    branches = [`report/exec-${date}`];
  }
  if (!branches) return null;

  for (const branch of branches) {
    const prs = await api(`/repos/${OWNER}/${REPO}/pulls?state=all&head=${OWNER}:${branch}`);
    if (prs && prs[0]) return prs[0];
  }
  return null;
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
  if (!el) { _resolveUserReady(); return; }
  if (!getToken()) { showAuth(); _resolveUserReady(); return; }
  try {
    const user = await getUser();
    if (user && user.login) {
      currentUser = user;
      el.innerHTML = `
        <div class="user-info">
          <img src="${user.avatar_url}" alt="${user.login}">
          <span>${user.login}</span>
          <button class="btn" onclick="clearToken();location.reload()">Sign out</button>
        </div>`;
    } else {
      clearToken();
      showAuth();
    }
  } catch {
    clearToken();
    showAuth();
  }
  _resolveUserReady();
}

// Sprint: sprint-task Issues + permanent-task Issues + bugs by priority + needs-review
async function getSprintPlan() {
  try {
    const [sprintOpen, sprintClosed, permanent, p0Bugs, p0Closed, p1Bugs, p2Bugs, needsReview] = await Promise.all([
      smartApi(`/repos/${OWNER}/${REPO}/issues?labels=sprint-task&state=open&per_page=30`),
      smartApi(`/repos/${OWNER}/${REPO}/issues?labels=sprint-task&state=closed&per_page=10&sort=updated&direction=desc`),
      smartApi(`/repos/${OWNER}/${REPO}/issues?labels=permanent-task&state=open&per_page=10`),
      smartApi(`/repos/${OWNER}/${REPO}/issues?labels=bug,P0&state=open&per_page=10`),
      smartApi(`/repos/${OWNER}/${REPO}/issues?labels=bug,P0&state=closed&per_page=10&sort=updated&direction=desc`),
      smartApi(`/repos/${OWNER}/${REPO}/issues?labels=bug,P1&state=open&per_page=10`),
      smartApi(`/repos/${OWNER}/${REPO}/issues?labels=bug,P2&state=open&per_page=10`),
      smartApi(`/repos/${OWNER}/${REPO}/issues?labels=needs-review&state=open&per_page=20`)
    ]);

    const mapIssue = i => ({
      name: i.title.replace(/^(Sprint|Permanent|Bug):\s*/i, ''),
      status: i.state === 'closed' ? 'done'
        : i.labels.some(l => l.name === 'in-progress') ? 'in-progress'
        : i.labels.some(l => l.name === 'needs-review') ? 'awaiting-approval'
        : 'pending',
      classification: i.labels.some(l => l.name === 'SENIOR') || i.labels.some(l => l.name === 'P0') ? 'SENIOR (Opus)' : 'JUNIOR (Sonnet)',
      priority: i.labels.find(l => ['P0','P1','P2'].includes(l.name))?.name || '',
      isPermanent: i.labels.some(l => l.name === 'permanent-task'),
      isBug: i.labels.some(l => l.name === 'bug'),
      isSenior: i.labels.some(l => l.name === 'SENIOR'),
      isRequested: i.labels.some(l => l.name === 'requested'),
      hasPlan: i.labels.some(l => l.name === 'plan-posted'),
      url: i.html_url,
      number: i.number,
      comments: i.comments
    });

    // All open bugs not yet in sprint (deduped against sprint-task issues)
    const sprintNumbers = new Set(sprintOpen.map(i => i.number));
    const seenBugIds = new Set();
    const openBugs = [...p0Bugs, ...p1Bugs, ...p2Bugs]
      .filter(i => !sprintNumbers.has(i.number) && !seenBugIds.has(i.number) && seenBugIds.add(i.number))
      .sort((a, b) => {
        const rank = { P0: 0, P1: 1, P2: 2 };
        const pa = a.labels.find(l => ['P0','P1','P2'].includes(l.name))?.name || 'P2';
        const pb = b.labels.find(l => ['P0','P1','P2'].includes(l.name))?.name || 'P2';
        return (rank[pa] ?? 3) - (rank[pb] ?? 3);
      });

    // Merge closed sprint-tasks and closed P0 bugs into one completed list, deduped
    const closedNumbers = new Set(sprintClosed.map(i => i.number));
    const dedupedP0Closed = p0Closed.filter(i => !closedNumbers.has(i.number));
    const allCompleted = [...sprintClosed, ...dedupedP0Closed]
      .sort((a, b) => new Date(b.updated_at) - new Date(a.updated_at))
      .slice(0, 10);

    // Bugs awaiting approval: needs-review + bug + plan-posted (no sprint-task yet)
    const awaitingApproval = needsReview.filter(i =>
      i.labels.some(l => l.name === 'bug') &&
      i.labels.some(l => l.name === 'plan-posted') &&
      !i.labels.some(l => l.name === 'sprint-task')
    );

    return {
      openBugs: openBugs.map(mapIssue),
      awaitingApproval: awaitingApproval.map(mapIssue),
      sprintTasks: sprintOpen.map(mapIssue),
      completedTasks: allCompleted.map(mapIssue),
      permanentTasks: permanent.map(mapIssue)
    };
  } catch (e) {
    console.error('[Sprint] Error:', e);
    return null;
  }
}

// Approve a bug for implementation (adds sprint-task only, removes needs-review)
// Any session (senior or junior) can pick up approved bugs based on priority queue order
async function approveBug(num, priority = '') {
  if (!isOwner()) { alert('Sign in as admin to approve'); return; }
  try {
    await api(`/repos/${OWNER}/${REPO}/issues/${num}/labels`, {
      method: 'POST',
      headers: { ...headers(), 'Content-Type': 'application/json' },
      body: JSON.stringify({ labels: ['sprint-task'] })
    });
    await api(`/repos/${OWNER}/${REPO}/issues/${num}/labels/needs-review`, { method: 'DELETE' });
    alert(`Issue #${num} approved — added to sprint queue.`);
    if (typeof loadSprint === 'function') loadSprint();
  } catch (e) {
    alert(`Failed: ${e.message}`);
  }
}

// Request a permanent task to run this cycle
async function requestPermanentTask(num) {
  if (!isOwner()) { alert('Sign in as admin'); return; }
  try {
    await api(`/repos/${OWNER}/${REPO}/issues/${num}/labels`, {
      method: 'POST',
      headers: { ...headers(), 'Content-Type': 'application/json' },
      body: JSON.stringify({ labels: ['requested'] })
    });
    await api(`/repos/${OWNER}/${REPO}/issues/${num}/comments`, {
      method: 'POST',
      headers: { ...headers(), 'Content-Type': 'application/json' },
      body: JSON.stringify({ body: 'Admin requested: run this in the next cycle.' })
    });
    alert(`Task #${num} requested for next cycle.`);
    if (typeof loadSprint === 'function') loadSprint();
  } catch (e) {
    alert(`Failed: ${e.message}`);
  }
}

// Toggle SENIOR flag on a permanent task
async function toggleSeniorFlag(num, isSenior) {
  if (!isOwner()) { alert('Sign in as admin'); return; }
  try {
    if (isSenior) {
      await api(`/repos/${OWNER}/${REPO}/issues/${num}/labels/SENIOR`, { method: 'DELETE' });
    } else {
      await api(`/repos/${OWNER}/${REPO}/issues/${num}/labels`, {
        method: 'POST',
        headers: { ...headers(), 'Content-Type': 'application/json' },
        body: JSON.stringify({ labels: ['SENIOR'] })
      });
    }
    if (typeof loadSprint === 'function') loadSprint();
  } catch (e) {
    alert(`Failed: ${e.message}`);
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

// Force TestFlight release via GitHub Issue
async function forceRelease() {
  if (!getToken()) { alert('Sign in first'); return; }
  if (!confirm('Force a TestFlight release? Preflight checks will still run.')) return;

  try {
    const issue = await api(`/repos/${OWNER}/${REPO}/issues`, {
      method: 'POST',
      headers: { ...headers(), 'Content-Type': 'application/json' },
      body: JSON.stringify({
        title: 'Force TestFlight Release',
        body: 'Triggered from Drift Command Center.\nThe autopilot will publish on its next commit cycle. Preflight checks will still run.',
        labels: ['force-release']
      })
    });
    alert(`Release triggered! Issue #${issue.number} created. The autopilot will pick it up on next commit (~2-3 min). Preflight still runs.`);
    // Refresh admin tab if visible
    if (typeof loadAdmin === 'function') loadAdmin();
  } catch (e) {
    alert(`Failed: ${e.message}`);
  }
}

// Get TestFlight status
async function getTestFlightStatus() {
  // Try metrics.json first
  const metrics = await getMetrics();
  if (metrics && metrics.lastTestFlight) {
    return { timestamp: new Date(metrics.lastTestFlight).getTime() / 1000 };
  }
  // Fallback: search commits for TestFlight builds (check more commits)
  try {
    const commits = await smartApi(`/repos/${OWNER}/${REPO}/commits?per_page=100`);
    const tfCommit = commits.find(c =>
      c.commit.message.includes('TestFlight build') ||
      c.commit.message.includes('TestFlight Build') ||
      c.commit.message.includes('chore: TestFlight')
    );
    if (tfCommit) {
      return {
        timestamp: new Date(tfCommit.commit.committer.date).getTime() / 1000,
        message: tfCommit.commit.message
      };
    }
  } catch (e) {
    console.error('TestFlight status error:', e);
  }
  return null;
}

function timeAgo(timestamp) {
  const now = Date.now() / 1000;
  const diff = now - timestamp;
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
  return `${Math.floor(diff / 86400)}d ago`;
}

function escapeHtml(str) {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}
