#!/usr/bin/env python3
"""Codex plan limits and OpenRouter balance for Quickshell.

Codex limits come from the server-side usage endpoint behind the Codex CLI
login (tokens live in CODEX_HOME/auth.json, refreshed automatically). If the
remote fetch fails we fall back to local Codex session events. OpenRouter
data comes from its documented /key and /credits endpoints. All fetches are
cached so dashboard opens stay instant.
"""
from __future__ import annotations

import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any


CODEX_HOME = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex")
AUTH_FILE = CODEX_HOME / "auth.json"
CODEX_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"
CODEX_USAGE_URL = "https://chatgpt.com/backend-api/codex/usage"
CACHE = Path(
    os.environ.get("AI_USAGE_CACHE")
    or Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
    / "quickshell"
    / "ai-usage.json"
)
OPENROUTER_KEY_FILES = (
    Path.home() / ".config" / "openrouter" / "api-key",
)
OPENROUTER_MANAGEMENT_KEY_FILES = (
    Path.home() / ".config" / "openrouter" / "management-key",
)
OPENROUTER_BASE = "https://openrouter.ai/api/v1"


def number(value: Any) -> float | None:
    try:
        return float(value) if value is not None else None
    except (TypeError, ValueError):
        return None


def money(value: Any) -> str:
    amount = number(value)
    if amount is None:
        return "--"
    amount = max(0.0, amount)
    return f"${amount:.2f}" if abs(amount - round(amount)) >= 0.005 else f"${amount:.0f}"


def local_reset(timestamp: Any) -> str:
    value = number(timestamp)
    if value is None:
        return ""
    reset = datetime.fromtimestamp(value).astimezone()
    now = datetime.now().astimezone()
    if reset.date() == now.date():
        return reset.strftime("%H:%M")
    return reset.strftime("%a %H:%M")


def token_expiry(token: str) -> float:
    """Return the JWT exp of an access/id token, 0 when unreadable."""
    try:
        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        claims = json.loads(base64.urlsafe_b64decode(payload))
        return number(claims.get("exp")) or 0.0
    except (IndexError, ValueError, json.JSONDecodeError, TypeError):
        return 0.0


def read_auth() -> dict[str, Any] | None:
    try:
        auth = json.loads(AUTH_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    tokens = auth.get("tokens") if isinstance(auth, dict) else None
    if not isinstance(tokens, dict) or not tokens.get("access_token"):
        return None
    return auth


def save_auth(auth: dict[str, Any]) -> None:
    """Persist refreshed tokens without changing auth.json permissions."""
    temporary = AUTH_FILE.with_suffix(".json.tmp")
    try:
        mode = AUTH_FILE.stat().st_mode & 0o777
    except OSError:
        mode = 0o600
    temporary.write_text(json.dumps(auth), encoding="utf-8")
    os.chmod(temporary, mode or 0o600)
    temporary.replace(AUTH_FILE)


def refresh_access_token(auth: dict[str, Any]) -> tuple[bool, str]:
    tokens = auth.get("tokens") or {}
    refresh_token = tokens.get("refresh_token")
    if not refresh_token:
        return False, "no refresh token"
    data = urllib.parse.urlencode(
        {
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
            "client_id": CODEX_CLIENT_ID,
        }
    ).encode()
    request = urllib.request.Request(
        "https://auth.openai.com/oauth/token",
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            body = json.load(response)
    except (urllib.error.HTTPError, urllib.error.URLError, ValueError) as exc:
        return False, f"token refresh failed: {exc}"
    access = body.get("access_token")
    if not access:
        return False, "token refresh returned no access_token"
    tokens["access_token"] = access
    tokens["id_token"] = body.get("id_token") or tokens.get("id_token")
    tokens["refresh_token"] = body.get("refresh_token") or refresh_token
    auth["last_refresh"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    save_auth(auth)
    return True, ""


def codex_live_usage() -> dict[str, Any]:
    """Fetch plan usage from the ChatGPT backend, falling back to local events.

    Returns the same shape as codex_usage() plus a "source" marker so the
    widget can tell server truth from rollout estimates.
    """
    auth = read_auth()
    if auth is None:
        local = codex_usage()
        local["source"] = "local"
        return local

    tokens = auth.get("tokens") or {}
    account_id = tokens.get("account_id") or ""
    access = tokens.get("access_token") or ""

    def request_with(token: str) -> tuple[Any, int, str]:
        request = urllib.request.Request(
            CODEX_USAGE_URL,
            headers={
                "Authorization": "Bearer " + token,
                "Accept": "application/json",
                "chatgpt-account-id": account_id,
                "User-Agent": "codex_cli_rs",
                "Origin": "https://chatgpt.com",
                "Referer": "https://chatgpt.com/codex/settings/usage",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                return json.load(response), response.status, ""
        except urllib.error.HTTPError as exc:
            try:
                body = json.loads(exc.read())
                message = str((body.get("error") or {}).get("message") or "")
            except (json.JSONDecodeError, AttributeError):
                message = ""
            return None, exc.code, message or f"HTTP {exc.code}"
        except (OSError, ValueError) as exc:
            return None, 0, str(exc)

    refreshed = False
    if not account_id or token_expiry(access) <= time.time() + 60:
        refreshed, error = refresh_access_token(auth)
        if refreshed:
            access = (auth.get("tokens") or {}).get("access_token") or access

    data, status, error = request_with(access)
    if data is None and status == 401 and not refreshed:
        refreshed, error = refresh_access_token(auth)
        if refreshed:
            access = (auth.get("tokens") or {}).get("access_token") or access
            data, status, error = request_with(access)

    payload = data if isinstance(data, dict) else None
    rate = (payload or {}).get("rate_limit") or {}
    primary = rate.get("primary_window") or {}
    secondary = rate.get("secondary_window") or {}
    if not isinstance(primary, dict) or not isinstance(secondary, dict):
        local = codex_usage()
        local["source"] = "local"
        local.setdefault("fetch_error", error or f"HTTP {status}")
        return local

    now = time.time()

    def window(source: dict[str, Any]) -> dict[str, Any]:
        used = number(source.get("used_percent")) or 0.0
        resets_at = number(source.get("reset_at")) or 0
        return {
            "remaining": max(0.0, min(100.0, 100.0 - used)),
            "resets_at": resets_at,
            "reset": local_reset(resets_at),
        }

    five = window(primary)
    week = window(secondary)
    credits = payload.get("credits") or {}
    credit_balance = money(credits.get("balance")) if credits.get("has_credits") else ""
    reset_credits = payload.get("rate_limit_reset_credits") or {}
    resets_left = number(reset_credits.get("applicable_available_count"))
    if resets_left is None:
        resets_left = number(reset_credits.get("available_count"))
    reset_bits = []
    if five["reset"]:
        reset_bits.append("5h resets " + five["reset"])
    if week["reset"]:
        reset_bits.append("week resets " + week["reset"])
    if resets_left is not None:
        reset_bits.append(f"{resets_left:.0f} reset{'s' if resets_left != 1 else ''} left")
    if credit_balance:
        reset_bits.append(credit_balance + " credits")

    return {
        "ok": True,
        "source": "live",
        "display": f"5h {five['remaining']:.0f}% · week {week['remaining']:.0f}%",
        "subtitle": " · ".join(reset_bits) or "Codex allowance",
        "five_hour_remaining": five["remaining"],
        "weekly_remaining": week["remaining"],
        "five_hour_reset": five["reset"],
        "weekly_reset": week["reset"],
        "resets_left": resets_left if resets_left is not None else -1,
        "credits": credit_balance,
        "plan": str(payload.get("plan_type") or ""),
        "updated_at": now,
        "stale": False,
    }


def read_last_rate_limits(path: Path) -> tuple[dict[str, Any] | None, float]:
    """Read a rollout backwards without loading a multi-megabyte file."""
    try:
        with path.open("rb") as handle:
            handle.seek(0, os.SEEK_END)
            position = handle.tell()
            pending = b""
            while position > 0:
                size = min(65536, position)
                position -= size
                handle.seek(position)
                pending = handle.read(size) + pending
                lines = pending.splitlines()
                pending = lines[0] if position else b""
                for raw in reversed(lines[1:] if position else lines):
                    if b'"rate_limits"' not in raw:
                        continue
                    try:
                        event = json.loads(raw)
                        limits = (event.get("payload") or {}).get("rate_limits")
                        if isinstance(limits, dict):
                            stamp = event.get("timestamp") or ""
                            fetched = datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp()
                            return limits, fetched
                    except (json.JSONDecodeError, TypeError, ValueError):
                        continue
    except OSError:
        pass
    return None, 0.0


def codex_usage() -> dict[str, Any]:
    session_root = CODEX_HOME / "sessions"
    try:
        candidates = sorted(
            session_root.rglob("*.jsonl"), key=lambda path: path.stat().st_mtime, reverse=True
        )[:12]
    except OSError:
        candidates = []

    newest: dict[str, Any] | None = None
    newest_at = 0.0
    for path in candidates:
        limits, fetched_at = read_last_rate_limits(path)
        if limits is not None and fetched_at > newest_at:
            newest = limits
            newest_at = fetched_at

    if newest is None:
        return {
            "ok": False,
            "display": "Use Codex once to load usage",
            "subtitle": "No local rate-limit event found",
            "five_hour_remaining": -1,
            "weekly_remaining": -1,
        }

    now = time.time()

    def window(name: str) -> dict[str, Any]:
        source = newest.get(name) or {}
        used = number(source.get("used_percent"))
        resets_at = number(source.get("resets_at"))
        # Once a recorded window expired, no use since means its allowance reset.
        remaining = 100.0 if resets_at and resets_at <= now else 100.0 - (used or 0.0)
        return {
            "remaining": max(0.0, min(100.0, remaining)),
            "resets_at": resets_at or 0,
            "reset": local_reset(resets_at),
        }

    five = window("primary")
    week = window("secondary")
    credits = newest.get("credits") or {}
    # Reset-credit counts only come from the live endpoint, not session events.
    credit_balance = money(credits.get("balance")) if credits.get("has_credits") else ""
    reset_bits = []
    if five["reset"]:
        reset_bits.append("5h resets " + five["reset"])
    if week["reset"]:
        reset_bits.append("week resets " + week["reset"])
    if credit_balance:
        reset_bits.append(credit_balance + " credits")

    return {
        "ok": True,
        "display": f"5h {five['remaining']:.0f}% · week {week['remaining']:.0f}%",
        "subtitle": " · ".join(reset_bits) or "Codex allowance",
        "five_hour_remaining": five["remaining"],
        "weekly_remaining": week["remaining"],
        "five_hour_reset": five["reset"],
        "weekly_reset": week["reset"],
        "resets_left": -1,
        "credits": credit_balance,
        "plan": str(newest.get("plan_type") or ""),
        "updated_at": newest_at,
        "stale": now - newest_at > 86400,
    }


def read_secret(env_name: str, paths: tuple[Path, ...]) -> str:
    value = os.environ.get(env_name, "").strip()
    if value:
        return value
    for path in paths:
        try:
            value = path.read_text(encoding="utf-8").strip()
        except OSError:
            continue
        if value:
            return value
    return ""


def openrouter_request(path: str, key: str) -> tuple[dict[str, Any] | None, str]:
    request = urllib.request.Request(
        OPENROUTER_BASE + path,
        headers={"Authorization": "Bearer " + key, "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            body = json.load(response)
            return body.get("data") if isinstance(body, dict) else None, ""
    except urllib.error.HTTPError as exc:
        try:
            body = json.loads(exc.read())
            message = str((body.get("error") or {}).get("message") or "")
        except (json.JSONDecodeError, AttributeError):
            message = ""
        return None, message or f"HTTP {exc.code}"
    except (OSError, ValueError) as exc:
        return None, str(exc)


def openrouter_usage() -> dict[str, Any]:
    api_key = read_secret("OPENROUTER_API_KEY", OPENROUTER_KEY_FILES)
    management_key = read_secret(
        "OPENROUTER_MANAGEMENT_KEY", OPENROUTER_MANAGEMENT_KEY_FILES
    )
    if not api_key and not management_key:
        return {
            "ok": False,
            "configured": False,
            "display": "Add OpenRouter key",
            "subtitle": "~/.config/openrouter/api-key",
            "remaining_percent": -1,
        }

    key_data = None
    credits_data = None
    errors: list[str] = []
    if api_key:
        key_data, error = openrouter_request("/key", api_key)
        if error:
            errors.append("key: " + error)

    credits_key = management_key or api_key
    if credits_key:
        credits_data, error = openrouter_request("/credits", credits_key)
        # A normal inference key is expected to receive 403 here.
        if error and management_key:
            errors.append("credits: " + error)

    key_limit = number((key_data or {}).get("limit"))
    key_remaining = number((key_data or {}).get("limit_remaining"))
    key_usage = number((key_data or {}).get("usage"))
    total_credits = number((credits_data or {}).get("total_credits"))
    total_usage = number((credits_data or {}).get("total_usage"))
    credit_remaining = (
        max(0.0, total_credits - total_usage)
        if total_credits is not None and total_usage is not None
        else None
    )

    if credit_remaining is not None:
        display = money(credit_remaining) + " credits left"
    elif key_remaining is not None:
        display = money(key_remaining) + " key limit left"
    elif key_data:
        display = money(key_usage) + " used · no key limit"
    else:
        display = "OpenRouter unavailable"

    bits = []
    if credit_remaining is not None:
        bits.append(money(total_usage) + " of " + money(total_credits) + " used")
    if key_remaining is not None:
        bits.append(money(key_remaining) + " key limit left")
    elif key_data:
        bits.append("key has no spending limit")
    if errors:
        bits.append("; ".join(errors))

    remaining_percent = -1.0
    if key_limit and key_remaining is not None:
        remaining_percent = max(0.0, min(100.0, key_remaining / key_limit * 100.0))
    elif total_credits and credit_remaining is not None:
        remaining_percent = max(0.0, min(100.0, credit_remaining / total_credits * 100.0))

    return {
        "ok": bool(key_data or credits_data),
        "configured": True,
        "display": display,
        "subtitle": " · ".join(bits) or (errors[0] if errors else "OpenRouter usage"),
        "remaining_percent": remaining_percent,
        "key_limit": key_limit,
        "key_remaining": key_remaining,
        "key_usage": key_usage,
        "credits_remaining": credit_remaining,
        "total_credits": total_credits,
        "total_usage": total_usage,
    }


def read_cache() -> dict[str, Any]:
    try:
        cached = json.loads(CACHE.read_text(encoding="utf-8"))
        return cached if isinstance(cached, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def write_cache(payload: dict[str, Any]) -> None:
    CACHE.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
    temporary = CACHE.with_suffix(".tmp")
    temporary.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
    temporary.chmod(0o600)
    temporary.replace(CACHE)


def combined(fetch_openrouter: bool, fetch_codex: bool) -> dict[str, Any]:
    cached = read_cache()
    router = cached.get("openrouter")
    if fetch_openrouter or not isinstance(router, dict):
        router = openrouter_usage()
    else:
        configured = bool(
            os.environ.get("OPENROUTER_API_KEY")
            or os.environ.get("OPENROUTER_MANAGEMENT_KEY")
            or any(path.is_file() for path in OPENROUTER_KEY_FILES)
            or any(path.is_file() for path in OPENROUTER_MANAGEMENT_KEY_FILES)
        )
        router.setdefault("configured", configured)

    if fetch_codex:
        codex = codex_live_usage()
        if codex.get("ok"):
            cached["codex"] = codex
    else:
        codex = cached.get("codex") or codex_usage()

    cached["openrouter"] = router
    cached["fetched_at"] = time.time()
    if fetch_openrouter or fetch_codex or "codex" not in cached:
        write_cache(cached)
    return {
        "codex": codex,
        "openrouter": router,
        "fetched_at": cached.get("fetched_at") or 0,
    }


def main() -> int:
    command = sys.argv[1] if len(sys.argv) > 1 else "status"
    if command not in ("status", "fetch"):
        print("usage: ai-usage.py [status|fetch]", file=sys.stderr)
        return 2
    print(json.dumps(combined(command == "fetch", command == "fetch"), separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
