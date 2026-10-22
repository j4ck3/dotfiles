#!/bin/bash
# Netdata metrics for Tower homeserver (Quickshell bar + popup).
set -euo pipefail

NETDATA_URL="${NETDATA_URL:-https://netdata.hjacke.com}"
CURL_OPTS=(--connect-timeout 2 --max-time 4 -sS)

fail_json() {
  local msg="${1:-unreachable}"
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"
  printf '{"ok":false,"label":"TOWER","text":"TOWER\\n--","value":"--","status":"offline","tooltip":"%s","class":"high"}\n' "$msg"
  exit 0
}

if ! command -v python3 >/dev/null 2>&1; then
  fail_json "python3 missing"
fi

info="$(curl "${CURL_OPTS[@]}" "${NETDATA_URL}/api/v1/info" 2>/dev/null)" || fail_json "netdata unreachable"
[[ -n "$info" ]] || fail_json "empty info"

metrics_file="$(mktemp)"
trap 'rm -f "$metrics_file"' EXIT
curl --connect-timeout 2 --max-time 8 -sS \
  "${NETDATA_URL}/api/v1/allmetrics?format=json&data=average" \
  >"$metrics_file" 2>/dev/null || : >"$metrics_file"

chart_data() {
  local chart="$1"
  curl "${CURL_OPTS[@]}" \
    "${NETDATA_URL}/api/v1/data?chart=${chart}&after=-60&points=1&group=average&format=json&options=absolute,jsonwrap" \
    2>/dev/null || true
}

cpu_raw="$(chart_data system.cpu)"
ram_raw="$(chart_data system.ram)"
load_raw="$(chart_data system.load)"
net_raw="$(chart_data system.net)"
uptime_raw="$(chart_data system.uptime)"

INFO="$info" \
METRICS_FILE="$metrics_file" \
CPU_RAW="$cpu_raw" \
RAM_RAW="$ram_raw" \
LOAD_RAW="$load_raw" \
NET_RAW="$net_raw" \
UPTIME_RAW="$uptime_raw" \
python3 <<'PY' || fail_json "parse failed"
import json
import os
import re
import sys

def load_obj(raw):
    if not raw or not raw.strip():
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None

def load_file(path):
    if not path or not os.path.isfile(path):
        return None
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError):
        return None

def chart_values(raw):
    obj = load_obj(raw)
    if not obj:
        return None, None
    names = obj.get("dimension_names") or []
    vals = obj.get("latest_values")
    if vals is None and obj.get("data"):
        vals = obj["data"][-1] if obj["data"] else None
    if not names or vals is None or len(names) != len(vals):
        return None, None
    return names, [float(v or 0) for v in vals]

def fmt_kib_rate(v):
    v = abs(float(v))
    if v >= 1048576:
        return f"{v / 1048576:.1f} GiB/s"
    if v >= 1024:
        return f"{v / 1024:.1f} MiB/s"
    return f"{v:.0f} KiB/s"

def fmt_size(mib):
    mib = float(mib)
    if mib >= 1048576:
        return f"{mib / 1048576:.1f} T"
    if mib >= 1024:
        return f"{mib / 1024:.1f} G"
    return f"{mib:.0f} M"

def fmt_uptime(secs):
    secs = max(0, int(float(secs)))
    days, rem = divmod(secs, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, _ = divmod(rem, 60)
    if days:
        return f"{days}d {hours}h"
    if hours:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"

def clean_name(name):
    if name.startswith("qemu_qemu_"):
        parts = name.split("-", 1)
        return parts[1] if len(parts) > 1 else name.replace("qemu_qemu_", "")
    return name.replace("_", " ")

def skip_cgroup(name):
    if not name or name.isdigit():
        return True
    if "docker_buildx_" in name and len(name) > 32:
        return True
    if re.fullmatch(r"[0-9a-f]{32,}", name):
        return True
    return False

info = load_obj(os.environ.get("INFO", ""))
if not info:
    sys.exit(1)

metrics = load_file(os.environ.get("METRICS_FILE", "")) or {}

alarms = info.get("alarms") or {}
warn = int(alarms.get("warning") or 0)
crit = int(alarms.get("critical") or 0)

cpu_names, cpu_vals = chart_values(os.environ.get("CPU_RAW", ""))
cpu = 0.0
if cpu_names and cpu_vals:
    cpu = sum(max(0.0, v) for v in cpu_vals)
cpu = int(round(cpu))

ram_names, ram_vals = chart_values(os.environ.get("RAM_RAW", ""))
ram_used_mib = 0.0
ram_total_mib = 0.0
if ram_names and ram_vals:
    dims = dict(zip(ram_names, ram_vals))
    used = float(dims.get("used") or 0)
    free = float(dims.get("free") or 0)
    cached = float(dims.get("cached") or 0)
    buffers = float(dims.get("buffers") or 0)
    ram_used_mib = used
    ram_total_mib = used + free + cached + buffers

ram_total_bytes = info.get("ram_total")
if ram_total_bytes:
    try:
        ram_total_mib = max(ram_total_mib, float(ram_total_bytes) / 1048576.0)
    except (TypeError, ValueError):
        pass

ram_pct = int(round(ram_used_mib * 100 / ram_total_mib)) if ram_total_mib > 0 else 0
ram_used_g = f"{ram_used_mib / 1024:.1f}"
ram_total_g = f"{ram_total_mib / 1024:.1f}"

load_names, load_vals = chart_values(os.environ.get("LOAD_RAW", ""))
load1 = load5 = load15 = 0.0
if load_names and load_vals:
    dims = dict(zip(load_names, load_vals))
    load1 = round(float(dims.get("load1") or 0), 2)
    load5 = round(float(dims.get("load5") or 0), 2)
    load15 = round(float(dims.get("load15") or 0), 2)

net_names, net_vals = chart_values(os.environ.get("NET_RAW", ""))
net_rx = net_tx = "0 KiB/s"
if net_names and net_vals:
    dims = dict(zip(net_names, net_vals))
    rx_key = "received" if "received" in dims else "InOctets"
    tx_key = "sent" if "sent" in dims else "OutOctets"
    net_rx = fmt_kib_rate(dims.get(rx_key) or 0)
    net_tx = fmt_kib_rate(dims.get(tx_key) or 0)

uptime_names, uptime_vals = chart_values(os.environ.get("UPTIME_RAW", ""))
uptime = "--"
if uptime_names and uptime_vals:
    uptime = fmt_uptime(uptime_vals[0])

top_ram = []
for key, chart in metrics.items():
    if not key.startswith("cgroup_") or not key.endswith(".mem_usage"):
        continue
    name = key[len("cgroup_") : -len(".mem_usage")]
    if skip_cgroup(name):
        continue
    dims = chart.get("dimensions") or {}
    ram_mib = float((dims.get("ram") or {}).get("value") or 0)
    if ram_mib < 32:
        continue
    top_ram.append((ram_mib, clean_name(name)))
top_ram.sort(key=lambda row: -row[0])
top_ram_out = [{"name": name, "ram": fmt_size(mib)} for mib, name in top_ram[:8]]

storage_used = storage_total = "--"
storage_pct = 0
def fmt_bytes_decimal(mib):
    # Decimal units, matching what Unraid shows for pool size/used.
    b = float(mib) * 1048576
    if b >= 1e12:
        return f"{b / 1e12:.2f} TB"
    if b >= 1e9:
        return f"{b / 1e9:.0f} GB"
    return f"{b / 1e6:.0f} MB"

# btrfs.data_* only covers allocated data chunks, which hides unallocated
# device space. btrfs.disk_* reports the whole device, so use it instead.
pools = []
for key, chart in metrics.items():
    if not key.startswith("btrfs.disk_"):
        continue
    dims = {
        name: float((dim or {}).get("value") or 0)
        for name, dim in (chart.get("dimensions") or {}).items()
    }
    total = sum(dims.values())
    used = dims.get("data_used", 0) + dims.get("meta_used", 0) + dims.get("sys_used", 0)
    if total <= 0:
        continue
    pools.append((total, used))
pools.sort(key=lambda row: -row[0])
if pools:
    total, used = pools[0]
    storage_used = fmt_bytes_decimal(used)
    storage_total = fmt_bytes_decimal(total)
    storage_pct = int(round(used * 100 / total))

os_name = info.get("os_name") or ""
os_version = info.get("os_version") or ""
host = f"{os_name} {os_version}".strip()
cores = info.get("cores_total") or "?"

if crit:
    status = f"{crit} crit"
elif warn:
    status = f"{warn} warn"
else:
    status = "online"

css = "high" if crit or warn else ""

out = {
    "ok": True,
    "label": "TOWER",
    "text": f"TOWER\\n{status}",
    "value": status,
    "cpu": cpu,
    "cores": str(cores),
    "ram_pct": ram_pct,
    "ram_used_g": ram_used_g,
    "ram_total_g": ram_total_g,
    "load1": load1,
    "load5": load5,
    "load15": load15,
    "net_rx": net_rx,
    "net_tx": net_tx,
    "uptime": uptime,
    "storage_used": storage_used,
    "storage_total": storage_total,
    "storage_pct": storage_pct,
    "top_ram": top_ram_out,
    "alarms_warn": warn,
    "alarms_crit": crit,
    "host": host,
    "tooltip": f"{host}\\nCPU {cpu}%  RAM {ram_pct}%  Load {load1}",
    "status": status,
    "class": css,
}

print(json.dumps(out, separators=(",", ":")))
PY
