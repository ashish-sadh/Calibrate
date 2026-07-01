"""Hermetic tests for scripts/is-clean-state.sh + the state.is_clean shaper (issue #907).

These run the REAL gate script against a throwaway git repo, a temp HOME, and a
temp Tier-0 cache path (via DRIFT_TIER0_CACHE_FILE) so nothing touches the
developer's working tree or the shared /tmp cache. No network: default cases use
commit subjects with no issue ref (head_verdict → treated PASS, no gh call) and
an absent in-progress file (no_claim_in_flight → true, no gh call).

Test-name conventions map to the issue's <done_when> verifier selectors:
  - criterion 1  →  `-k 'fast or timeout'`
  - criterion 2  →  `-k 'tier0 or unknown'`
  - criterion 3  →  `-k non_empty_reason`
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]  # drift-mcp/tests/ -> repo root
SCRIPT = REPO_ROOT / "scripts" / "is-clean-state.sh"

_HAS_TIMEOUT = bool(shutil.which("timeout") or shutil.which("gtimeout"))


def _git_env() -> dict:
    return {
        **os.environ,
        "GIT_AUTHOR_NAME": "t",
        "GIT_AUTHOR_EMAIL": "t@t",
        "GIT_COMMITTER_NAME": "t",
        "GIT_COMMITTER_EMAIL": "t@t",
    }


def _init_repo(path: Path, subject: str = "init commit") -> None:
    env = _git_env()
    subprocess.run(["git", "init", "-q"], cwd=path, check=True, env=env)
    (path / "tracked.txt").write_text("hello")
    subprocess.run(["git", "add", "."], cwd=path, check=True, env=env)
    subprocess.run(["git", "commit", "-q", "-m", subject], cwd=path, check=True, env=env)


def _run_gate(
    repo: Path,
    home: Path,
    cache_file: Path | None,
    extra_env: dict | None = None,
    path_prepend: str | None = None,
):
    """Run is-clean-state.sh --report; return (proc, parsed_json, elapsed_seconds)."""
    env = {**os.environ}
    env["HOME"] = str(home)
    # A None cache_file means "point at a path that does not exist".
    env["DRIFT_TIER0_CACHE_FILE"] = str(cache_file if cache_file is not None else home / "no_cache.json")
    env.pop("DRIFT_GATE_TIMEOUT", None)
    env.pop("DRIFT_TIER0_CACHE_TTL", None)
    if path_prepend:
        env["PATH"] = f"{path_prepend}:{env['PATH']}"
    if extra_env:
        env.update(extra_env)
    start = time.monotonic()
    proc = subprocess.run(
        [str(SCRIPT), "--report"],
        cwd=repo,
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )
    elapsed = time.monotonic() - start
    data = json.loads(proc.stdout) if proc.stdout.strip() else {}
    return proc, data, elapsed


@pytest.fixture()
def repo_home(tmp_path: Path):
    repo = tmp_path / "repo"
    repo.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    return repo, home


# ── criterion 1: fast return + per-check timeout yields a reason, never hangs ──


def test_returns_fast_with_missing_cache(repo_home, tmp_path):
    repo, home = repo_home
    _init_repo(repo)
    proc, data, elapsed = _run_gate(repo, home, cache_file=tmp_path / "nope.json")
    assert elapsed < 5.0, f"gate took {elapsed:.1f}s — should be near-instant with cache-only Tier-0"
    assert proc.returncode == 0, data  # clean tree + tier0_unknown(non-blocking)
    assert "checks" in data and "dirty_reasons" in data  # always-valid JSON


@pytest.mark.skipif(not _HAS_TIMEOUT, reason="no timeout/gtimeout binary to enforce per-check cap")
def test_gh_check_timeout_yields_reason_not_hang(repo_home, tmp_path):
    repo, home = repo_home
    # Commit references an issue → head_verdict shells out to `gh`.
    _init_repo(repo, subject="fix(#999): needs a gh verdict lookup")
    # Fake, slow `gh` on PATH; a 1s gate timeout must cut it off well before 10s.
    fakebin = tmp_path / "fakebin"
    fakebin.mkdir()
    gh = fakebin / "gh"
    gh.write_text("#!/bin/bash\nsleep 10\n")
    gh.chmod(0o755)
    proc, data, elapsed = _run_gate(
        repo,
        home,
        cache_file=tmp_path / "nope.json",
        extra_env={"DRIFT_GATE_TIMEOUT": "1"},
        path_prepend=str(fakebin),
    )
    assert elapsed < 6.0, f"gate waited {elapsed:.1f}s — the per-check timeout did not fire"
    assert proc.returncode != 0
    assert any("timed out" in r for r in data["dirty_reasons"]), data


# ── criterion 2: Tier-0 is cache-only; missing/stale → tier0_unknown; never inline ──


def test_tier0_gate_never_runs_swift_test_inline():
    # Ignore comment/doc lines — assert no executable line invokes the suite.
    code_lines = [
        ln for ln in SCRIPT.read_text().splitlines()
        if ln.strip() and not ln.lstrip().startswith("#")
    ]
    assert not any("swift test" in ln for ln in code_lines), "gate must never invoke `swift test` inline"


def test_tier0_default_cache_path_matches_verify_writer():
    # The gate must read the SAME path drift-mcp verify.py writes (underscore),
    # not the old split-brain hyphen path.
    text = SCRIPT.read_text()
    assert "/tmp/drift_mcp_tier0_cache.json" in text
    assert "/tmp/drift-mcp_tier0_cache.json" not in text


def test_tier0_missing_cache_reports_unknown(repo_home, tmp_path):
    repo, home = repo_home
    _init_repo(repo)
    proc, data, _ = _run_gate(repo, home, cache_file=tmp_path / "absent.json")
    t0 = data["checks"]["tier0_tests"]
    assert t0["pass"] is True  # non-blocking
    assert "unknown" in t0.get("detail", "").lower(), t0
    assert proc.returncode == 0


def test_tier0_stale_cache_reports_unknown(repo_home, tmp_path):
    repo, home = repo_home
    _init_repo(repo)
    cache = tmp_path / "cache.json"
    cache.write_text(json.dumps({"at": time.time() - 10_000, "passing": True, "output_tail": "old"}))
    proc, data, _ = _run_gate(repo, home, cache_file=cache)
    t0 = data["checks"]["tier0_tests"]
    assert t0["pass"] is True
    assert "unknown" in t0.get("detail", "").lower(), t0
    assert proc.returncode == 0


def test_tier0_fresh_pass_cache_is_used(repo_home, tmp_path):
    repo, home = repo_home
    _init_repo(repo)
    cache = tmp_path / "cache.json"
    # Mirror verify.py's json.dumps output: float `at`, ": " separators.
    cache.write_text(json.dumps({"at": time.time(), "passing": True, "output_tail": "ok"}))
    proc, data, _ = _run_gate(repo, home, cache_file=cache)
    t0 = data["checks"]["tier0_tests"]
    assert t0["pass"] is True
    assert "cached pass" in t0.get("detail", ""), t0
    assert proc.returncode == 0


# ── criterion 3: non-empty reason whenever clean:false ──


def test_dirty_working_tree_non_empty_reason(repo_home, tmp_path):
    repo, home = repo_home
    _init_repo(repo)
    (repo / "uncommitted.txt").write_text("dirty")  # untracked → dirty tree
    proc, data, _ = _run_gate(repo, home, cache_file=tmp_path / "nope.json")
    assert proc.returncode != 0
    assert data["dirty_reasons"], "clean:false must carry a reason"
    assert any("working_tree" in r for r in data["dirty_reasons"]), data


def test_failing_tier0_cache_non_empty_reason(repo_home, tmp_path):
    repo, home = repo_home
    _init_repo(repo)
    cache = tmp_path / "cache.json"
    cache.write_text(json.dumps({"at": time.time(), "passing": False, "output_tail": "boom"}))
    proc, data, _ = _run_gate(repo, home, cache_file=cache)
    assert proc.returncode != 0
    assert data["dirty_reasons"]
    assert any("tier0" in r.lower() for r in data["dirty_reasons"]), data


def test_report_is_valid_json_with_non_empty_reason_on_exit_nonzero(repo_home, tmp_path):
    repo, home = repo_home
    _init_repo(repo)
    (repo / "x.txt").write_text("y")
    proc, data, _ = _run_gate(repo, home, cache_file=tmp_path / "nope.json")
    assert proc.returncode != 0
    # JSON parsed (no exception above) AND reasons non-empty.
    assert isinstance(data.get("dirty_reasons"), list) and data["dirty_reasons"]


def test_state_shaper_synthesizes_non_empty_reason_on_empty_stdout():
    # The MCP wrapper must never surface clean:false with no reason even when the
    # script emits nothing (killed before --report). Tests the pure shaper.
    from drift_mcp.tools.state import _shape_clean_result

    shaped = _shape_clean_result({"ok": False, "exit": 124, "stdout": "", "stderr": "timeout after 60s"})
    assert shaped["clean"] is False
    assert shaped["dirty_reasons"], "empty-stdout nonzero exit must synthesize a reason"
    assert any("124" in r or "timeout" in r for r in shaped["dirty_reasons"])


def test_state_shaper_passes_through_clean():
    from drift_mcp.tools.state import _shape_clean_result

    shaped = _shape_clean_result(
        {"ok": True, "exit": 0, "stdout": json.dumps({"checks": {}, "dirty_reasons": []}), "stderr": ""}
    )
    assert shaped["clean"] is True
    assert shaped["dirty_reasons"] == []
