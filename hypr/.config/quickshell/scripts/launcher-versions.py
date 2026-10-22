#!/usr/bin/env python3
"""Stream complete launcher version snapshots, without running application binaries.

stdout is JSON Lines for QML SplitParser. Diagnostics go to stderr and the cache's
errors map. Latest versions expire after one hour, including when refresh fails.
Pacman versions are package versions (epoch/pkgrel included), not upstream tags.
Flatpak identity includes installation, origin, architecture and branch. A commit
is never a version. Unmanaged apps and missing version metadata remain unknown.
"""

from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime
import json
import math
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

TTL = 3600
LOCAL_TIMEOUT = 8
CACHE_VERSION = 1


class MetadataError(Exception):
    pass


def run(argv, *, timeout=LOCAL_TIMEOUT, env=None, allowed=(0,)):
    """Bound the whole process group, including checkupdates' pacman children."""
    environment = dict(os.environ, LC_ALL="C", LANG="C", NO_COLOR="1")
    if env:
        environment.update(env)
    try:
        process = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, env=environment, start_new_session=True)
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
            raise MetadataError(f"{argv[0]} timed out after {timeout}s") from None
    except OSError as error:
        raise MetadataError(f"{argv[0]}: {error}") from error
    if process.returncode not in allowed:
        raise MetadataError(f"{argv[0]} exited {process.returncode}: {stderr.strip()[:400]}")
    return stdout


def diagnostic(source, error):
    print(f"launcher-versions [{source}]: {error}", file=sys.stderr, flush=True)


@dataclass(frozen=True)
class Desktop:
    id: str
    filename: str
    command: str
    flatpak: str = ""


@dataclass(frozen=True)
class Target:
    kind: str
    name: str
    repo: str = ""
    installation: str = ""
    origin: str = ""
    arch: str = ""
    branch: str = ""
    installed_commit: str = ""
    repo_known: bool = True

    @property
    def source(self):
        if self.kind == "flatpak":
            return f"flatpak:{self.installation}:{self.origin}:app/{self.name}/{self.arch}/{self.branch}"
        if self.kind == "pacman":
            prefix = "pacman" if self.repo_known else "pacman-configured"
            return f"{prefix}:{self.repo}/{self.name}"
        return f"{self.kind}:{self.name}"

    @property
    def ref(self):
        return f"app/{self.name}/{self.arch}/{self.branch}"

    @property
    def scope(self):
        if self.installation in ("system", "user"):
            return "--" + self.installation
        return "--installation=" + self.installation


def desktop_entries():
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio
    try:
        gi.require_version("GioUnix", "2.0")
        from gi.repository import GioUnix
        desktop_type = GioUnix.DesktopAppInfo
    except (ValueError, ImportError):
        desktop_type = Gio.DesktopAppInfo

    def convert(app):
        filename = app.get_filename()
        return Desktop(app.get_id().removesuffix(".desktop"), filename,
                       app.get_commandline() or "", app.get_string("X-Flatpak") or "")

    entries = {}
    for app in Gio.AppInfo.get_all():
        if hasattr(app, "get_filename") and app.get_filename():
            entry = convert(app)
            entries[entry.id] = entry
    # SSH and minimal sessions may omit Flatpak exports from XDG_DATA_DIRS.
    roots = [Path.home() / ".local/share/flatpak/exports/share/applications",
             Path("/var/lib/flatpak/exports/share/applications")]
    for root in roots:
        for filename in sorted(root.glob("*.desktop")):
            app = desktop_type.new_from_filename(str(filename))
            if app:
                entry = convert(app)
                entries.setdefault(entry.id, entry)
    return list(entries.values())


def executable(command):
    """Resolve Exec without executing it. Do not mistake a URL handler for its app."""
    try:
        words = shlex.split(command)
    except ValueError:
        return None
    if not words:
        return None
    if Path(words[0]).name == "env":
        words.pop(0)
        while words and ("=" in words[0] and not words[0].startswith("-")):
            words.pop(0)
        if words and words[0] == "--":
            words.pop(0)
    if not words or words[0].startswith("-"):
        return None
    if Path(words[0]).name in {"sh", "bash", "python", "python3", "node", "flatpak", "wine", "java"}:
        return None
    if any("://" in word for word in words[1:]):
        return None
    return shutil.which(words[0])


def ownership_paths(entry):
    paths = [entry.filename]
    # A user desktop file commonly changes only Exec or visibility. Its exact
    # system desktop ID is stronger evidence than the wrapper script's owner.
    data_dirs = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
    for directory in data_dirs:
        candidate = Path(directory) / "applications" / (entry.id + ".desktop")
        if candidate.is_file() and str(candidate) not in paths:
            paths.append(str(candidate))
    binary = executable(entry.command)
    if binary:
        paths.append(binary)
        resolved = os.path.realpath(binary)
        if resolved != binary:
            paths.append(resolved)
    return paths


def package_owners(paths):
    owners = {}
    paths = sorted(set(paths))
    for offset in range(0, len(paths), 100):
        output = run(["pacman", "-Qo", "--", *paths[offset:offset + 100]], allowed=tuple(range(101)))
        for line in output.splitlines():
            match = re.fullmatch(r"(.+) is owned by (\S+) (\S+)", line)
            if match:
                owners[match[1]] = (match[2], match[3])
    return owners


def repo_packages(output):
    result = {}
    for line in output.splitlines():
        fields = line.split()
        if len(fields) >= 3:
            repo, name, version = fields[:3]
            # pacman -Sl preserves configured repository priority.
            result.setdefault(name, (repo, version))
    return result


def flatpak_installed():
    output = run(["flatpak", "list", "--app",
                  "--columns=application,version,branch,arch,origin,installation"])
    result = []
    for line in output.splitlines():
        fields = line.split("\t")
        if len(fields) == 6:
            name, version, branch, arch, origin, installation = fields
            if all((name, branch, arch, origin, installation)):
                result.append((Target("flatpak", name, installation=installation,
                                      origin=origin, arch=arch, branch=branch), version or None))
    return result


def select_flatpak(entry, installed):
    if not entry.flatpak:
        return None
    try:
        words = shlex.split(entry.command)
    except ValueError:
        return None
    options = {}
    for index, word in enumerate(words):
        for key in ("branch", "arch", "installation"):
            if word.startswith(f"--{key}="):
                options[key] = word.split("=", 1)[1]
            elif word == f"--{key}" and index + 1 < len(words):
                options[key] = words[index + 1]
    filename = os.path.realpath(entry.filename)
    if "--user" in words or "/.local/share/flatpak/" in filename:
        options["installation"] = "user"
    elif "--system" in words or filename.startswith("/var/lib/flatpak/"):
        options["installation"] = "system"
    matches = [(target, version) for target, version in installed
               if target.name == entry.flatpak
               and all(getattr(target, key) == value for key, value in options.items())]
    # An ambiguous branch/installation must not silently pick stable or system.
    return matches[0] if len(matches) == 1 else None


def package_metadata():
    root = Path(run(["pacman-conf", "DBPath"]).strip()) / "local"
    result = {}
    for filename in root.glob("*/desc"):
        try:
            text = filename.read_text()
            fields = {}
            for match in re.finditer(r"%([A-Z_]+)%\n([^\n]+)", text):
                fields[match[1]] = match[2]
            def number(key):
                value = fields.get(key, "")
                return int(value) if value.isdigit() else None
            if "NAME" in fields:
                result[fields["NAME"]] = {
                    "size_bytes": number("SIZE"), "installed_at": number("INSTALLDATE"),
                    "built_at": number("BUILDDATE"), "repo": fields.get("INSTALLED_DB"),
                }
        except (OSError, ValueError) as error:
            diagnostic("pacman:metadata", error)
    return result


def flatpak_details(target):
    output = run(["flatpak", "info", target.scope, "--arch=" + target.arch,
                  target.name, target.branch])
    fields = dict((key.strip(), value.strip()) for line in output.splitlines()
                  for key, sep, value in [line.partition(":")] if sep)
    if fields.get("Ref") != target.ref or fields.get("Origin") != target.origin:
        raise MetadataError("Installed Flatpak identity changed during inventory")
    size = run(["flatpak", "info", target.scope, "--arch=" + target.arch,
                "--show-size", target.name, target.branch]).strip()
    committed = None
    try:
        committed = datetime.strptime(fields.get("Date", ""), "%Y-%m-%d %H:%M:%S %z").timestamp()
    except ValueError:
        pass
    return {"size_bytes": int(size) if size.isdigit() else None,
            "committed_at": committed}, fields.get("Commit", "")


def update_command(target):
    # Returned as data only. The UI must require an explicit click and an
    # interactive terminal. Never run these commands from the metadata worker.
    if not target:
        return None
    if target.kind == "pacman":
        return ["sudo", "pacman", "-Syu"]
    if target.kind == "aur" and shutil.which("paru"):
        return ["paru", "-Syu"]
    if target.kind == "flatpak":
        return ["flatpak", "update", target.scope, target.ref]
    return None


def inventory(entries, errors):
    apps, targets = {}, {}

    def attempt(source, function, fallback):
        try:
            return function()
        except Exception as error:
            errors[source] = {"message": str(error), "at": time.time()}
            diagnostic(source, error)
            return fallback

    metadata = attempt("pacman:metadata", package_metadata, {})
    flatpaks = attempt("flatpak:installed", flatpak_installed, [])
    paths = {entry.id: ownership_paths(entry) for entry in entries if not entry.flatpak}
    owners = attempt("pacman:ownership", lambda: package_owners(
        [path for candidates in paths.values() for path in candidates]), {})
    repos = attempt("pacman:local-repositories", lambda: repo_packages(run(["pacman", "-Sl"])), {})
    foreign = attempt("pacman:foreign", lambda: set(run(["pacman", "-Qmq"]).splitlines()), set())
    for entry in entries:
        target, version = None, None
        details = {}
        if entry.flatpak:
            selected = select_flatpak(entry, flatpaks)
            if selected:
                target, version = selected
                details, commit = attempt(target.source + ":installed",
                                          lambda: flatpak_details(target), ({}, ""))
                target = Target("flatpak", target.name, installation=target.installation,
                                origin=target.origin, arch=target.arch, branch=target.branch,
                                installed_commit=commit)
        else:
            owner = next((owners[path] for path in paths[entry.id] if path in owners), None)
            if owner:
                name, version = owner
                details = dict(metadata.get(name, {}))
                installed_repo = details.pop("repo", None)
                if name in foreign:
                    target = Target("aur", name)
                elif installed_repo and installed_repo != "local":
                    target = Target("pacman", name, repo=installed_repo)
                elif name in repos:
                    target = Target("pacman", name, repo=repos[name][0], repo_known=False)
                else:
                    target = Target("unresolved", name)
        source = target.source if target else "unknown"
        apps[entry.id] = {
            "installed": version, "latest": None, "source": source, "checked_at": None,
            "manager": target.kind if target and target.kind != "unresolved" else "unknown",
            "package": target.name if target else None,
            "size_bytes": None, "installed_at": None, "built_at": None,
            "released_at": None, "committed_at": None,
            "status": "unknown", "update_command": update_command(target), **details,
        }
        if target:
            targets[source] = target
    return apps, targets


def fresh_repos(targets):
    # checkupdates -d is deliberately never used. The fresh temporary DB is not
    # shared with pacman or other helper instances and disappears after this read.
    with tempfile.TemporaryDirectory(prefix="launcher-versions-db-") as database:
        run(["checkupdates", "--nocolor"], timeout=40,
            env={"CHECKUPDATES_DB": database}, allowed=(0, 2))
        output = run(["pacman", "--dbpath", database, "-Sl"], timeout=10)
    versions = {}
    for line in output.splitlines():
        fields = line.split()
        if len(fields) >= 3:
            versions[(fields[0], fields[1])] = fields[2]
    return {target.source: versions.get((target.repo, target.name)) for target in targets}


def aur_versions(targets):
    result = {target.source: None for target in targets}
    names = {target.name: target.source for target in targets}
    for offset in range(0, len(names), 100):
        batch = list(names)[offset:offset + 100]
        query = urllib.parse.urlencode([("arg[]", name) for name in batch])
        request = urllib.request.Request("https://aur.archlinux.org/rpc/v5/info?" + query,
                                         headers={"User-Agent": "quickshell-launcher-versions/1"})
        try:
            with urllib.request.urlopen(request, timeout=12) as response:
                raw = response.read(2_000_001)
            if len(raw) > 2_000_000:
                raise MetadataError("AUR response exceeds size limit")
            payload = json.loads(raw)
        except (OSError, ValueError) as error:
            raise MetadataError(f"AUR RPC: {error}") from error
        if payload.get("type") != "multiinfo" or not isinstance(payload.get("results"), list):
            raise MetadataError("AUR RPC returned an error or malformed results")
        for package in payload["results"]:
            name, version = package.get("Name"), package.get("Version")
            if name in batch and isinstance(version, str) and version:
                result[names[name]] = version
    return result


def flatpak_latest(target):
    output = run(["flatpak", "remote-info", target.scope, target.origin, target.ref], timeout=15)
    fields = {}
    for line in output.splitlines():
        key, separator, value = line.strip().partition(":")
        if separator:
            fields[key] = value.strip()
    if fields.get("Ref") != target.ref:
        raise MetadataError("Flatpak remote returned a different or missing ref")
    # Version is AppStream metadata selected by flatpak for this exact remote ref.
    # Commit, Subject, runtime version and default-branch search are not fallbacks.
    version = fields.get("Version") or None
    if version and re.fullmatch(r"[0-9a-fA-F]{40,64}", version):
        version = None
    return {target.source: {"latest": version, "latest_commit": fields.get("Commit")}}


def cache_path():
    return Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "quickshell/launcher-versions.json"


def load_cache(path):
    try:
        payload = json.loads(path.read_text())
        if payload.get("version") == CACHE_VERSION and isinstance(payload.get("entries"), dict):
            return payload
    except (OSError, ValueError, AttributeError):
        pass
    return {"version": CACHE_VERSION, "entries": {}, "errors": {}}


def valid_cached(entry, now):
    if not isinstance(entry, dict):
        return False
    checked = entry.get("checked_at")
    latest = entry.get("latest")
    return (isinstance(checked, (int, float)) and not isinstance(checked, bool)
            and math.isfinite(checked) and 0 <= now - checked < TTL
            and (latest is None or isinstance(latest, str)))


def apply_cache(apps, cache, now, targets=None):
    for app in apps.values():
        cached = cache["entries"].get(app["source"])
        if valid_cached(cached, now):
            app.update(latest=cached["latest"], checked_at=cached["checked_at"])
        else:
            app.update(latest=None, checked_at=None)
        app["status"] = version_status(app, cached if valid_cached(cached, now) else None,
                                       (targets or {}).get(app["source"]))


def version_status(app, cached, target=None):
    if not cached or not app.get("installed") or not app.get("latest"):
        return "unknown"
    if app.get("manager") == "flatpak":
        remote_commit = cached.get("latest_commit")
        if target and target.installed_commit and remote_commit:
            return "current" if target.installed_commit == remote_commit else "update_available"
        return "unknown"
    if app.get("manager") not in ("pacman", "aur"):
        return "unknown"
    try:
        comparison = int(run(["vercmp", app["installed"], app["latest"]], timeout=2).strip())
    except (MetadataError, ValueError):
        return "unknown"
    return "ahead" if comparison > 0 else "update_available" if comparison < 0 else "current"


def save_cache(path, cache):
    temporary = None
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile("w", dir=path.parent, prefix=path.name + ".", delete=False) as stream:
            temporary = stream.name
            json.dump(cache, stream, allow_nan=False)
        os.replace(temporary, path)
    except (OSError, ValueError) as error:
        diagnostic("cache", error)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


def emit(apps, refreshing):
    print(json.dumps({"apps": apps, "refreshing": refreshing}, separators=(",", ":"), allow_nan=False), flush=True)


def main(refresh=False):
    emit({}, True)
    path = cache_path()
    cache = load_cache(path)
    if not isinstance(cache.get("errors"), dict):
        cache["errors"] = {}
    errors = cache["errors"]
    try:
        entries = desktop_entries()
        apps, targets = inventory(entries, errors)
    except Exception as error:
        diagnostic("inventory", error)
        errors["inventory"] = {"message": str(error), "at": time.time()}
        save_cache(path, cache)
        emit({}, False)
        return
    now = time.time()
    cache["entries"] = {key: value for key, value in cache["entries"].items()
                        if key in targets and valid_cached(value, now)}
    apply_cache(apps, cache, now, targets)
    pending = [target for source, target in targets.items()
               if (refresh or source not in cache["entries"]) and target.kind != "unresolved"]
    emit(apps, bool(pending))
    if not pending:
        save_cache(path, cache)
        return
    tasks = []
    repos = [target for target in pending if target.kind == "pacman"]
    aur = [target for target in pending if target.kind == "aur"]
    if repos:
        tasks.append((repos, fresh_repos, repos))
    if aur:
        tasks.append((aur, aur_versions, aur))
    tasks.extend(([target], flatpak_latest, target) for target in pending if target.kind == "flatpak")
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = {pool.submit(function, argument): group for group, function, argument in tasks}
        remaining = len(futures)
        for future in as_completed(futures):
            group = futures[future]
            checked = time.time()
            try:
                versions = future.result()
                for source, latest in versions.items():
                    cache["entries"][source] = {**(latest if isinstance(latest, dict) else {"latest": latest}),
                                                "checked_at": checked}
                    errors.pop(source, None)
            except Exception as error:
                for target in group:
                    errors[target.source] = {"message": str(error), "at": checked}
                    diagnostic(target.source, error)
            remaining -= 1
            apply_cache(apps, cache, checked, targets)
            emit(apps, remaining > 0)
    save_cache(path, cache)


if __name__ == "__main__":
    try:
        main(refresh="--refresh" in sys.argv[1:])
    except BrokenPipeError:
        # The launcher can close its reader while an asynchronous check finishes.
        sys.stdout = open(os.devnull, "w")
