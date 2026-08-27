#!/usr/bin/env python3
"""Cursor usage from daily Helium cookies. Unofficial dashboard API."""
from __future__ import annotations

import json
import os
import shutil
import sqlite3
import sys
import tempfile
import time
import urllib.error
import urllib.request
from http.cookiejar import Cookie, CookieJar
from pathlib import Path

CACHE = Path(os.environ.get("CURSOR_USAGE_CACHE", "")).expanduser()
UNIX_TO_NT_EPOCH_OFFSET = 11644473600

COOKIE_CANDIDATES = [
    Path(os.environ["CURSOR_USAGE_COOKIE_FILE"]).expanduser()
    if os.environ.get("CURSOR_USAGE_COOKIE_FILE")
    else None,
    Path.home() / ".config/net.imput.helium/Default/Cookies",
    Path.home() / ".config/net.imput.helium/Default/Network/Cookies",
]


def write_cache(payload: dict) -> None:
    CACHE.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
    payload["fetched_at"] = time.time()
    tmp = CACHE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
    tmp.replace(CACHE)


def num(v):
    if v is None or v is False:
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def parse_usage(summary: dict) -> dict:
    plan = (summary.get("individualUsage") or {}).get("plan") or {}
    on_demand = (summary.get("individualUsage") or {}).get("onDemand") or {}
    membership = summary.get("membershipType") or ""
    pct = num(plan.get("totalPercentUsed"))
    auto_pct = num(plan.get("autoPercentUsed"))
    api_pct = num(plan.get("apiPercentUsed"))
    start = (summary.get("billingCycleStart") or "")[:10]
    end = (summary.get("billingCycleEnd") or "")[:10]

    if pct is None:
        display = "--"
    else:
        display = f"{int(round(pct))}%"

    css = "high" if pct is not None and pct >= 90 else ""
    bits = []
    if membership:
        bits.append(str(membership))
    if start or end:
        bits.append(f"{start or '?'} → {end or '?'}")
    msg = summary.get("autoModelSelectedDisplayMessage") or ""
    if msg:
        bits.append(msg)
    if auto_pct is not None:
        bits.append(f"auto {int(round(auto_pct))}%")
    if api_pct is not None:
        bits.append(f"API {int(round(api_pct))}%")
    od_used, od_lim = num(on_demand.get("used")), num(on_demand.get("limit"))
    if on_demand.get("enabled") and od_used is not None:
        if od_lim:
            bits.append(f"on-demand {od_used:g}/{od_lim:g}")
        else:
            bits.append(f"on-demand {od_used:g}")

    return {
        "ok": True,
        "need_login": False,
        "error": "",
        "membership": membership,
        "display": display,
        "percent": pct,
        "class": css,
        "tooltip": "\n".join(bits) or "Cursor usage",
    }


def _aes_key():
    from Cryptodome.Protocol.KDF import PBKDF2

    return PBKDF2(b"peanuts", b"saltysalt", dkLen=16, count=1)


def _decrypt_v10(blob: bytes, strip_domain_hash: bool) -> str | None:
    from Cryptodome.Cipher import AES
    from Cryptodome.Util.Padding import unpad

    if blob[:3] != b"v10":
        return None
    try:
        pt = unpad(AES.new(_aes_key(), AES.MODE_CBC, iv=b" " * 16).decrypt(blob[3:]), 16)
    except ValueError:
        return None
    if strip_domain_hash:
        pt = pt[32:]
    try:
        return pt.decode("utf-8")
    except UnicodeDecodeError:
        return None


def _copy_cookie_db(src: Path) -> Path:
    tmp = Path(tempfile.mkdtemp(prefix="qs-cursor-cookies-"))
    for extra in ("", "-wal", "-journal"):
        p = src if extra == "" else Path(str(src) + extra)
        if p.is_file():
            shutil.copy2(p, tmp / p.name)
    return tmp / src.name


def load_cookiejar() -> tuple[CookieJar | None, str]:
    last = "no Helium cookie db"
    for path in COOKIE_CANDIDATES:
        if path is None or not path.is_file():
            continue
        try:
            db = _copy_cookie_db(path)
            con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
            con.text_factory = bytes
            try:
                ver_row = con.execute(
                    "SELECT value FROM meta WHERE key = 'version'"
                ).fetchone()
                strip = False
                if ver_row:
                    raw = ver_row[0]
                    if isinstance(raw, bytes):
                        raw = raw.decode("utf-8", "replace")
                    try:
                        strip = int(raw) >= 24
                    except (TypeError, ValueError):
                        strip = False
                rows = con.execute(
                    """
                    SELECT host_key, path, is_secure, expires_utc, name,
                           value, encrypted_value, is_httponly
                    FROM cookies
                    WHERE host_key LIKE '%cursor.com'
                    """
                ).fetchall()
            finally:
                con.close()
        except Exception as exc:
            last = f"{path}: {exc}"
            continue

        cj = CookieJar()
        has_session = False
        for host_b, path_b, secure, expires_nt, name_b, value_b, enc, http_only in rows:
            host = host_b.decode("utf-8", "replace") if isinstance(host_b, bytes) else host_b
            cpath = path_b.decode("utf-8", "replace") if isinstance(path_b, bytes) else path_b
            name = name_b.decode("utf-8", "replace") if isinstance(name_b, bytes) else name_b
            if value_b:
                value = value_b.decode("utf-8", "replace") if isinstance(value_b, bytes) else value_b
            else:
                value = _decrypt_v10(enc or b"", strip) or ""
            if not value:
                continue
            if name == "WorkosCursorSessionToken":
                has_session = True
            expires = None
            if expires_nt:
                expires = int(expires_nt / 1000000 - UNIX_TO_NT_EPOCH_OFFSET)
            cj.set_cookie(
                Cookie(
                    version=0,
                    name=name,
                    value=value,
                    port=None,
                    port_specified=False,
                    domain=host,
                    domain_specified=True,
                    domain_initial_dot=host.startswith("."),
                    path=cpath or "/",
                    path_specified=True,
                    secure=bool(secure),
                    expires=expires,
                    discard=not expires,
                    comment=None,
                    comment_url=None,
                    rest={"HttpOnly": ""} if http_only else {},
                    rfc2109=False,
                )
            )
        shutil.rmtree(db.parent, ignore_errors=True)
        if has_session:
            return cj, str(path)
        last = f"{path}: no session cookie"
    return None, last


def http_json(opener, url: str) -> tuple[int, dict | None, str]:
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": "Mozilla/5.0",
        },
    )
    try:
        with opener.open(req, timeout=20) as resp:
            raw = resp.read()
            try:
                return resp.status, json.loads(raw), ""
            except json.JSONDecodeError:
                return resp.status, None, raw[:200].decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        body = exc.read()
        try:
            obj = json.loads(body)
        except json.JSONDecodeError:
            obj = None
        err = ""
        if isinstance(obj, dict):
            err = str(obj.get("error") or obj.get("description") or "")
        return exc.code, obj, err or body[:200].decode("utf-8", "replace")
    except Exception as exc:
        return 0, None, str(exc)


def fetch() -> dict:
    cj, src = load_cookiejar()
    if cj is None:
        return {
            "ok": False,
            "need_login": True,
            "error": src,
            "display": "login",
            "class": "high",
            "tooltip": "Log in to cursor.com in Helium, then refresh",
        }

    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    status, summary, err = http_json(opener, "https://cursor.com/api/usage-summary")
    if status in (401, 403) or (
        isinstance(summary, dict) and "not_authenticated" in str(summary.get("error", ""))
    ):
        return {
            "ok": False,
            "need_login": True,
            "error": err or "not logged in",
            "display": "login",
            "class": "high",
            "tooltip": "Helium session expired — open cursor.com in Helium",
        }
    if status != 200 or not isinstance(summary, dict):
        return {
            "ok": False,
            "need_login": False,
            "error": err or f"http {status}",
            "display": "--",
            "class": "high",
            "tooltip": err or f"usage-summary http {status}",
        }
    parsed = parse_usage(summary)
    parsed["cookie_src"] = Path(src).parent.parent.name
    return parsed


def main() -> int:
    if not CACHE:
        print("CURSOR_USAGE_CACHE unset", file=sys.stderr)
        return 2
    try:
        payload = fetch()
    except Exception as exc:
        payload = {
            "ok": False,
            "need_login": False,
            "error": str(exc)[:240],
            "display": "--",
            "class": "high",
            "tooltip": str(exc)[:200],
        }
    write_cache(payload)
    print(json.dumps(payload, separators=(",", ":")))
    return 0 if payload.get("ok") or payload.get("need_login") else 1


if __name__ == "__main__":
    sys.exit(main())
