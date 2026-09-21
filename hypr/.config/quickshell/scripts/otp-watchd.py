#!/usr/bin/env python3
"""Outlook/live.se OTP watcher for Quickshell.

Default: IMAP + Thunderbird public OAuth client (no Azure portal / no paid sub).
Idle until armed (PowerMenu). Armed → poll inbox every 2s → OTP → wl-copy +
notify-send → idle.

Config + tokens: ~/.config/qs-otp/ (never in repo). See otp-watch.README.
"""

from __future__ import annotations

import argparse
import email as email_lib
import imaplib
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from email.header import decode_header, make_header
from email.utils import parseaddr, parsedate_to_datetime
from pathlib import Path

try:
    import httpx
    import msal
except ImportError as e:
    print(
        "missing deps — use ~/.config/qs-otp/venv (msal + httpx)\n"
        f"  ({e})",
        file=sys.stderr,
    )
    sys.exit(1)

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib  # type: ignore

CONFIG_DIR = Path(os.environ.get("QS_OTP_CONFIG", Path.home() / ".config" / "qs-otp"))
CACHE_DIR = Path(os.environ.get("QS_OTP_CACHE", Path.home() / ".cache" / "quickshell"))
STATE_PATH = CACHE_DIR / "otp-watch.json"
CONFIG_PATH = CONFIG_DIR / "config.toml"
TOKEN_CACHE_PATH = CONFIG_DIR / "msal_token.json"

# Mozilla Thunderbird public client — personal Outlook/live IMAP OAuth, no Azure app.
THUNDERBIRD_CLIENT_ID = "9e5f94bc-e8a4-4e73-b8be-63364c29d753"
IMAP_HOST = "outlook.office365.com"
IMAP_SCOPES = [
    "https://outlook.office.com/IMAP.AccessAsUser.All",
]
GRAPH = "https://graph.microsoft.com/v1.0"
GRAPH_SCOPES = ["https://graph.microsoft.com/Mail.Read"]
DEFAULT_AUTHORITY = "https://login.microsoftonline.com/consumers"

IDLE_SLEEP_S = 1.0
ARMED_POLL_S = 2.0
ARMED_TIMEOUT_S = 5 * 60
CHIP_TTL_S = 60
MSG_TOP = 10
# Accept mail slightly older than arm click (request OTP → open PowerMenu lag).
LOOKBACK_S = 3 * 60

HINT_RE = re.compile(
    r"(?:verification|verify|one[-\s]?time|otp|pass\s?code|security\s?code|"
    r"login\s?code|sign[-\s]?in\s?code|authentication\s?code|"
    r"eng[aå]ngs|verifierings|s[aä]kerhetskod|inloggningskod|kod)",
    re.I,
)
CODE_RE = re.compile(r"(?<![A-Za-z0-9])(\d{4,8})(?![A-Za-z0-9])")
BAD_CODE_RE = re.compile(
    r"^(?:19\d{2}|20[0-3]\d|1000|0000|1234|123456|111111|000000)$"
)


def _now() -> float:
    return time.time()


def _atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".otp-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def default_state() -> dict:
    return {
        "mode": "idle",
        "armed_at": 0,
        "code": "",
        "from": "",
        "subject": "",
        "found_at": 0,
        "expires_at": 0,
        "ok": True,
        "error": "",
    }


def read_state() -> dict:
    if not STATE_PATH.exists():
        st = default_state()
        write_state(st)
        return st
    try:
        data = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return default_state()
    out = default_state()
    out.update({k: data.get(k, out[k]) for k in out})
    return out


def write_state(st: dict) -> None:
    _atomic_write(STATE_PATH, json.dumps(st, ensure_ascii=False) + "\n")


def update_state(**kwargs) -> dict:
    st = read_state()
    st.update(kwargs)
    write_state(st)
    return st


def load_config() -> dict:
    if not CONFIG_PATH.exists():
        raise FileNotFoundError(
            f"missing {CONFIG_PATH} — see otp-watch.README"
        )
    with CONFIG_PATH.open("rb") as f:
        cfg = tomllib.load(f)
    email = (cfg.get("email") or "").strip()
    client_id = (cfg.get("client_id") or THUNDERBIRD_CLIENT_ID).strip()
    backend = (cfg.get("backend") or "imap").strip().lower()
    if not email:
        raise ValueError(f"set email in {CONFIG_PATH}")
    if client_id.startswith("YOUR-"):
        raise ValueError(f"set client_id in {CONFIG_PATH}")
    if backend not in ("imap", "graph"):
        raise ValueError("backend must be imap or graph")
    return {
        "email": email,
        "client_id": client_id,
        "backend": backend,
        "authority": (cfg.get("authority") or DEFAULT_AUTHORITY).strip(),
        "imap_host": (cfg.get("imap_host") or IMAP_HOST).strip(),
    }


def scopes_for(cfg: dict) -> list[str]:
    return list(GRAPH_SCOPES if cfg["backend"] == "graph" else IMAP_SCOPES)


def build_app(cfg: dict) -> msal.PublicClientApplication:
    CONFIG_DIR.mkdir(parents=True, mode=0o700, exist_ok=True)
    cache = msal.SerializableTokenCache()
    if TOKEN_CACHE_PATH.exists():
        cache.deserialize(TOKEN_CACHE_PATH.read_text(encoding="utf-8"))

    def persist() -> None:
        if cache.has_state_changed:
            _atomic_write(TOKEN_CACHE_PATH, cache.serialize())
            os.chmod(TOKEN_CACHE_PATH, 0o600)

    app = msal.PublicClientApplication(
        cfg["client_id"],
        authority=cfg["authority"],
        token_cache=cache,
    )
    app._qs_persist = persist  # type: ignore[attr-defined]
    return app


def persist_cache(app: msal.PublicClientApplication) -> None:
    fn = getattr(app, "_qs_persist", None)
    if callable(fn):
        fn()


def acquire_token(app: msal.PublicClientApplication, cfg: dict, interactive: bool) -> str:
    scopes = scopes_for(cfg)
    accounts = app.get_accounts(username=cfg["email"])
    result = None
    if accounts:
        result = app.acquire_token_silent(scopes, account=accounts[0])
    if not result:
        accounts = app.get_accounts()
        if accounts:
            result = app.acquire_token_silent(scopes, account=accounts[0])

    if result and "access_token" in result:
        persist_cache(app)
        return result["access_token"]

    if not interactive:
        raise RuntimeError("not logged in — run: otp-watch.sh login")

    flow = app.initiate_device_flow(scopes=scopes)
    if "user_code" not in flow:
        raise RuntimeError(f"device flow failed: {json.dumps(flow)}")
    print(flow["message"], flush=True)
    result = app.acquire_token_by_device_flow(flow)
    persist_cache(app)
    if "access_token" not in result:
        raise RuntimeError(result.get("error_description") or json.dumps(result))
    return result["access_token"]


def decode_mime(value: str | None) -> str:
    if not value:
        return ""
    try:
        return str(make_header(decode_header(value)))
    except Exception:
        return value


def strip_html(html: str) -> str:
    text = re.sub(r"(?is)<(script|style).*?>.*?</\1>", " ", html)
    text = re.sub(r"(?s)<[^>]+>", " ", text)
    text = re.sub(r"&\w+;", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def extract_otp(subject: str, preview: str, body: str = "") -> str | None:
    blob = "\n".join(x for x in (subject, preview, body) if x)
    if not blob.strip():
        return None

    for m in HINT_RE.finditer(blob):
        window = blob[max(0, m.start() - 40) : m.end() + 80]
        codes = [c for c in CODE_RE.findall(window) if not BAD_CODE_RE.match(c)]
        codes.sort(key=lambda c: (abs(len(c) - 6), -len(c)))
        if codes:
            return codes[0]

    subj_codes = [c for c in CODE_RE.findall(subject or "") if not BAD_CODE_RE.match(c)]
    if subj_codes:
        subj_codes.sort(key=lambda c: (abs(len(c) - 6), -len(c)))
        return subj_codes[0]

    if HINT_RE.search(blob):
        codes = [c for c in CODE_RE.findall(blob) if not BAD_CODE_RE.match(c)]
        codes.sort(key=lambda c: (abs(len(c) - 6), -len(c)))
        if codes:
            return codes[0]
    return None


def parse_graph_time(s: str | None) -> float:
    if not s:
        return 0.0
    try:
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        return datetime.fromisoformat(s).timestamp()
    except ValueError:
        return 0.0


def msg_body_text(msg: email_lib.message.Message) -> str:
    parts: list[str] = []
    if msg.is_multipart():
        for part in msg.walk():
            ctype = part.get_content_type()
            if ctype == "text/plain":
                try:
                    parts.append(part.get_payload(decode=True).decode(  # type: ignore[union-attr]
                        part.get_content_charset() or "utf-8", errors="replace"
                    ))
                except Exception:
                    pass
            elif ctype == "text/html" and not parts:
                try:
                    raw = part.get_payload(decode=True).decode(  # type: ignore[union-attr]
                        part.get_content_charset() or "utf-8", errors="replace"
                    )
                    parts.append(strip_html(raw))
                except Exception:
                    pass
    else:
        try:
            raw = msg.get_payload(decode=True)
            if isinstance(raw, bytes):
                text = raw.decode(msg.get_content_charset() or "utf-8", errors="replace")
            else:
                text = str(msg.get_payload() or "")
            if msg.get_content_type() == "text/html":
                text = strip_html(text)
            parts.append(text)
        except Exception:
            pass
    return "\n".join(parts)


def wl_copy(code: str) -> None:
    try:
        subprocess.run(["wl-copy", "--", code], check=False, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        pass


def notify(code: str, frm: str) -> None:
    body = f"{code} · {frm}" if frm else code
    try:
        subprocess.run(
            ["notify-send", "-a", "qs-otp", "-u", "normal", "OTP", body],
            check=False,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass


def on_hit(code: str, frm: str, subject: str) -> None:
    now = _now()
    update_state(
        mode="idle",
        code=code,
        **{"from": frm},
        subject=subject,
        found_at=now,
        expires_at=now + CHIP_TTL_S,
        ok=True,
        error="",
    )
    wl_copy(code)
    notify(code, frm)
    print(f"otp hit: {code} from {frm}", flush=True)


def imap_connect(cfg: dict, token: str) -> imaplib.IMAP4_SSL:
    imap = imaplib.IMAP4_SSL(cfg["imap_host"])
    user = cfg["email"]

    def _auth(_challenge: bytes | None) -> bytes:
        return f"user={user}\x01auth=Bearer {token}\x01\x01".encode()

    typ, _ = imap.authenticate("XOAUTH2", _auth)
    if typ != "OK":
        raise RuntimeError(f"IMAP AUTH failed: {typ}")
    typ, _ = imap.select("INBOX", readonly=True)
    if typ != "OK":
        raise RuntimeError("IMAP SELECT INBOX failed")
    return imap


def imap_close(imap: imaplib.IMAP4_SSL | None) -> None:
    if imap is None:
        return
    try:
        imap.close()
    except Exception:
        pass
    try:
        imap.logout()
    except Exception:
        pass


def scan_imap(imap: imaplib.IMAP4_SSL, armed_at: float) -> bool:
    cutoff = armed_at - LOOKBACK_S
    # Outlook commonly exposes Junk; Spam is used by some IMAP providers.
    for folder in ("INBOX", "Junk", "Spam"):
        typ, _ = imap.select(folder, readonly=True)
        if typ != "OK":
            continue
        typ, data = imap.search(None, "ALL")
        if typ != "OK" or not data or data[0] is None:
            continue
        ids = data[0].split()
        for num in reversed(ids[-MSG_TOP:]):
            typ, msg_data = imap.fetch(num, "(RFC822)")
            if typ != "OK" or not msg_data or not msg_data[0]:
                continue
            raw = msg_data[0][1]
            if not isinstance(raw, (bytes, bytearray)):
                continue
            msg = email_lib.message_from_bytes(raw)
            date_hdr = msg.get("Date")
            recv = 0.0
            if date_hdr:
                try:
                    dt = parsedate_to_datetime(date_hdr)
                    if dt.tzinfo is None:
                        dt = dt.replace(tzinfo=timezone.utc)
                    recv = dt.timestamp()
                except Exception:
                    recv = 0.0
            if recv and recv + 2 < cutoff:
                continue
            subject = decode_mime(msg.get("Subject"))
            _name, addr = parseaddr(msg.get("From") or "")
            frm = decode_mime(msg.get("From") or "") or addr or "mail"
            body = msg_body_text(msg)
            code = extract_otp(subject, body[:500], body)
            if code:
                on_hit(code, frm, subject)
                return True
    return False


def graph_get(token: str, path: str, params: dict | None = None) -> dict:
    with httpx.Client(timeout=20.0) as client:
        r = client.get(
            f"{GRAPH}{path}",
            headers={"Authorization": f"Bearer {token}"},
            params=params or {},
        )
        if r.status_code >= 400:
            raise RuntimeError(f"graph {r.status_code}: {r.text[:300]}")
        return r.json()


def scan_graph(token: str, armed_at: float) -> bool:
    cutoff = armed_at - LOOKBACK_S
    for folder in ("inbox", "junkemail"):
        data = graph_get(
            token,
            f"/me/mailFolders/{folder}/messages",
            {
                "$top": str(MSG_TOP),
                "$orderby": "receivedDateTime desc",
                "$select": "id,from,subject,bodyPreview,receivedDateTime,body",
            },
        )
        for msg in data.get("value") or []:
            recv = parse_graph_time(msg.get("receivedDateTime"))
            if recv and recv + 2 < cutoff:
                continue
            subject = msg.get("subject") or ""
            preview = msg.get("bodyPreview") or ""
            body_obj = msg.get("body") or {}
            raw_body = body_obj.get("content") or ""
            if (body_obj.get("contentType") or "").lower() == "html":
                raw_body = strip_html(raw_body)
            fr = (msg.get("from") or {}).get("emailAddress") or {}
            name = (fr.get("name") or "").strip()
            addr = (fr.get("address") or "").strip()
            frm = f"{name} <{addr}>" if name and addr else (name or addr or "mail")
            code = extract_otp(subject, preview, raw_body)
            if code:
                on_hit(code, frm, subject)
                return True
    return False


def cmd_login() -> int:
    try:
        cfg = load_config()
    except (FileNotFoundError, ValueError, OSError) as e:
        print(str(e), file=sys.stderr)
        return 1
    app = build_app(cfg)
    acquire_token(app, cfg, interactive=True)
    update_state(ok=True, error="")
    print(f"login ok — backend={cfg['backend']} token cached", flush=True)
    return 0


def cmd_daemon() -> int:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    if not STATE_PATH.exists():
        write_state(default_state())

    cfg = None
    app = None
    token = None
    token_exp = 0.0
    imap: imaplib.IMAP4_SSL | None = None

    while True:
        st = read_state()
        mode = st.get("mode") or "idle"

        if mode != "armed":
            if imap is not None:
                imap_close(imap)
                imap = None
            time.sleep(IDLE_SLEEP_S)
            continue

        armed_at = float(st.get("armed_at") or 0)
        if armed_at <= 0:
            armed_at = _now()
            update_state(armed_at=armed_at)

        if _now() - armed_at > ARMED_TIMEOUT_S:
            update_state(mode="idle", ok=True, error="armed timeout")
            imap_close(imap)
            imap = None
            print("armed timeout → idle", flush=True)
            continue

        try:
            if cfg is None:
                cfg = load_config()
                app = build_app(cfg)
            if token is None or _now() >= token_exp:
                assert app is not None
                token = acquire_token(app, cfg, interactive=False)
                token_exp = _now() + 50 * 60
                imap_close(imap)
                imap = None
            assert token is not None

            if cfg["backend"] == "graph":
                found = scan_graph(token, armed_at)
            else:
                if imap is None:
                    imap = imap_connect(cfg, token)
                try:
                    found = scan_imap(imap, armed_at)
                except Exception:
                    imap_close(imap)
                    imap = None
                    raise

            update_state(ok=True, error="")
            if found:
                imap_close(imap)
                imap = None
                continue
        except Exception as e:
            update_state(ok=False, error=str(e)[:200])
            print(f"otp-watchd error: {e}", file=sys.stderr, flush=True)
            imap_close(imap)
            imap = None
            time.sleep(ARMED_POLL_S)
            continue

        time.sleep(ARMED_POLL_S)


def main() -> int:
    ap = argparse.ArgumentParser(description="QS Outlook OTP watcher")
    ap.add_argument(
        "--login",
        action="store_true",
        help="interactive device-code login, then exit",
    )
    args = ap.parse_args()
    if args.login:
        return cmd_login()
    return cmd_daemon()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(0)
