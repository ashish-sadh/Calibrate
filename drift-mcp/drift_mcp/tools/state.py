"""State accessors — cleanliness gate, control signal, in-progress issue."""

from __future__ import annotations

import json
import os
from pathlib import Path

from drift_mcp.runner import run_script


def _shape_clean_result(result: dict) -> dict:
    """Shape a run_script() result of is-clean-state.sh --report into the tool payload.

    The gate script always emits JSON with a populated `dirty_reasons` on a
    nonzero exit. But if it was killed before it could emit (external timeout,
    crash) stdout is empty/unparseable — in that case synthesize a reason so
    callers never see a reasonless clean:false (issue #907).
    """
    stdout = result.get("stdout", "") or ""
    try:
        data = json.loads(stdout) if stdout.strip() else {}
    except json.JSONDecodeError:
        data = {}
    clean = result.get("ok", False)
    dirty_reasons = data.get("dirty_reasons", []) or []
    if not clean and not dirty_reasons:
        exit_code = result.get("exit", "?")
        detail = (result.get("stderr", "") or "").strip() or stdout.strip() or "no report emitted"
        dirty_reasons = [f"is-clean-state.sh exited {exit_code} without a report: {detail[:200]}"]
    return {
        "ok": True,
        "clean": clean,  # exit 0 = clean
        "dirty_reasons": dirty_reasons,
        "checks": data.get("checks", {}),
        "stdout_raw": stdout,
    }


def _control_file() -> Path:
    return Path(os.environ.get("HOME", "")) / "drift-control.txt"


def _in_progress_file() -> Path:
    return Path(os.environ.get("HOME", "")) / "drift-state" / "in-progress-issue"


def register(mcp) -> None:
    @mcp.tool()
    def state_is_clean() -> dict:
        """Check if main is in a complete-unit-of-work state.

        Returns `{clean: bool, dirty_reasons: [...]}`. Used by /testflight-publish
        skill, /senior claim, /junior claim, and any future trigger that should
        only fire on stable state.
        """
        result = run_script("scripts/is-clean-state.sh", ["--report"])
        # Convention: stdout is JSON when --report flag is passed.
        return _shape_clean_result(result)

    @mcp.tool()
    def state_control_signal() -> dict:
        """Read ~/drift-control.txt; return PAUSE | DRAIN | RUN (default RUN if missing)."""
        f = _control_file()
        if not f.exists():
            return {"ok": True, "signal": "RUN"}
        signal = f.read_text(encoding="utf-8").strip().upper()
        if signal not in {"PAUSE", "DRAIN", "RUN"}:
            return {"ok": True, "signal": "RUN", "raw": signal, "warning": "unrecognized; defaulting to RUN"}
        return {"ok": True, "signal": signal}

    @mcp.tool()
    def state_in_progress_issue() -> dict:
        """Return the issue number currently claimed by a session, or None."""
        f = _in_progress_file()
        if not f.exists():
            return {"ok": True, "issue": None}
        content = f.read_text(encoding="utf-8").strip()
        if not content:
            return {"ok": True, "issue": None}
        try:
            return {"ok": True, "issue": int(content)}
        except ValueError:
            return {"ok": True, "issue": None, "raw": content}
