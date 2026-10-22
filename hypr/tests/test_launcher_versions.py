"""Read-only metadata tests. No package manager or network calls escape mocks."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

HELPER = Path(__file__).resolve().parents[1] / ".config/quickshell/scripts/launcher-versions.py"
SPEC = importlib.util.spec_from_file_location("launcher_versions", HELPER)
m = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = m
SPEC.loader.exec_module(m)


class VersionTests(unittest.TestCase):
    def test_local_override_prefers_system_counterpart(self):
        entry = m.Desktop("editor", "/home/test/.local/share/applications/editor.desktop", "/wrapper/editor")
        with patch.object(m.Path, "is_file", return_value=True), patch.object(m, "executable", return_value="/wrapper/editor"):
            paths = m.ownership_paths(entry)
        self.assertEqual(paths[0], entry.filename)
        self.assertLess(paths.index("/usr/share/applications/editor.desktop"), paths.index("/wrapper/editor"))

    def test_exec_env_is_resolved_without_running_app(self):
        with patch.object(m.shutil, "which", return_value="/usr/bin/editor") as which:
            self.assertEqual(m.executable("env BACKEND=wayland editor %U"), "/usr/bin/editor")
            which.assert_called_once_with("editor")
        self.assertIsNone(m.executable("steam steam://rungameid/730"))
        self.assertIsNone(m.executable("python /unmanaged/script.py"))

    def test_ownership_keeps_success_when_other_paths_unowned(self):
        with patch.object(m, "run", return_value="/usr/bin/editor is owned by editor-bin 2:4.1-3\n") as run:
            self.assertEqual(m.package_owners(["/missing", "/usr/bin/editor"]),
                             {"/usr/bin/editor": ("editor-bin", "2:4.1-3")})
            self.assertIn(17, run.call_args.kwargs["allowed"])

    def test_repos_use_exact_name_and_repository(self):
        target = m.Target("pacman", "browser-nightly", repo="testing")
        with patch.object(m, "run", side_effect=["", "extra browser 5\nextra browser-nightly 8\ntesting browser-nightly 7\n"]) as run:
            self.assertEqual(m.fresh_repos([target]), {target.source: "7"})
        first = run.call_args_list[0]
        self.assertEqual(first.args[0], ["checkupdates", "--nocolor"])
        database = first.kwargs["env"]["CHECKUPDATES_DB"]
        self.assertNotEqual(database, "/var/lib/pacman")
        self.assertIn(database, run.call_args_list[1].args[0])
        self.assertFalse(Path(database).exists())

    def test_repo_refresh_failure_never_uses_stale_db(self):
        with patch.object(m, "run", side_effect=m.MetadataError("offline")) as run:
            with self.assertRaises(m.MetadataError):
                m.fresh_repos([m.Target("pacman", "editor", repo="extra")])
        self.assertEqual(run.call_count, 1)

    def test_aur_exact_foreign_name_no_bin_or_git_substitution(self):
        targets = [m.Target("aur", "editor-bin"), m.Target("aur", "editor-git")]
        payload = {"type": "multiinfo", "results": [
            {"Name": "editor", "Version": "999"}, {"Name": "editor-bin", "Version": "2-1"}]}
        response = unittest.mock.MagicMock()
        response.__enter__.return_value.read.return_value = json.dumps(payload).encode()
        with patch.object(m.urllib.request, "urlopen", return_value=response) as request:
            self.assertEqual(m.aur_versions(targets), {"aur:editor-bin": "2-1", "aur:editor-git": None})
            url = request.call_args.args[0].full_url
            self.assertIn("editor-bin", url)
            self.assertIn("editor-git", url)

    def test_aur_error_is_not_a_successful_unknown(self):
        response = unittest.mock.MagicMock()
        response.__enter__.return_value.read.return_value = b'{"type":"error","error":"offline"}'
        with patch.object(m.urllib.request, "urlopen", return_value=response):
            with self.assertRaises(m.MetadataError):
                m.aur_versions([m.Target("aur", "editor")])

    def test_flatpak_same_origin_branch_arch_and_installation(self):
        stable = m.Target("flatpak", "org.App", installation="system", origin="flathub", arch="x86_64", branch="stable")
        beta = m.Target("flatpak", "org.App", installation="user", origin="testing", arch="aarch64", branch="beta")
        entry = m.Desktop("org.App", "/home/test/.local/share/applications/org.App.desktop",
                          "flatpak run --user --branch=beta --arch=aarch64 org.App", "org.App")
        self.assertEqual(m.select_flatpak(entry, [(stable, "1"), (beta, "2")]), (beta, "2"))
        ambiguous = m.Desktop("org.App", "/custom/org.App.desktop", "flatpak run org.App", "org.App")
        self.assertIsNone(m.select_flatpak(ambiguous, [(stable, "1"), (beta, "2")]))
        with patch.object(m, "run", return_value=f"Ref: {beta.ref}\nVersion: 2.3-beta\nCommit: abc\n") as run:
            self.assertEqual(m.flatpak_latest(beta)[beta.source]["latest"], "2.3-beta")
        self.assertEqual(run.call_args.args[0], ["flatpak", "remote-info", "--user", "testing", beta.ref])
        self.assertEqual(m.update_command(beta), ["flatpak", "update", "--user", beta.ref])

    def test_flatpak_commit_is_not_version(self):
        target = m.Target("flatpak", "org.App", installation="system", origin="flathub", arch="x86_64", branch="stable")
        with patch.object(m, "run", return_value=f"Ref: {target.ref}\nCommit: {'a' * 64}\n"):
            self.assertIsNone(m.flatpak_latest(target)[target.source]["latest"])
        with patch.object(m, "run", return_value="Ref: app/org.App/x86_64/beta\nVersion: 99\n"):
            with self.assertRaises(m.MetadataError):
                m.flatpak_latest(target)

    def test_cache_expires_after_one_hour_and_rejects_future(self):
        self.assertTrue(m.valid_cached({"latest": "1", "checked_at": 1}, 3600))
        self.assertFalse(m.valid_cached({"latest": "1", "checked_at": 1}, 3601))
        self.assertFalse(m.valid_cached({"latest": "1", "checked_at": 9999}, 100))
        self.assertFalse(m.valid_cached({"latest": "1", "checked_at": float("nan")}, 100))
        apps = {"app": {"source": "aur:app", "installed": "1", "latest": "9", "checked_at": 1}}
        m.apply_cache(apps, {"entries": {"aur:app": {"latest": "9", "checked_at": 1}}}, 4000)
        self.assertIsNone(apps["app"]["latest"])

    def test_version_comparison_uses_pacman_semantics(self):
        app = {"manager": "pacman", "installed": "2:1-1", "latest": "1:99-3"}
        with patch.object(m, "run", return_value="1\n") as run:
            self.assertEqual(m.version_status(app, {"checked_at": 1}), "ahead")
            self.assertEqual(run.call_args.args[0], ["vercmp", "2:1-1", "1:99-3"])

    def test_missing_metadata_never_uses_installed_as_latest(self):
        app = {"manager": "pacman", "installed": "1", "latest": None}
        self.assertEqual(m.version_status(app, {"checked_at": 1}), "unknown")

    def test_inventory_failures_preserve_unknown_apps_and_errors(self):
        entries = [m.Desktop("editor", "/unknown/editor.desktop", "editor")]
        errors = {}
        with patch.object(m, "run", side_effect=m.MetadataError("missing")), \
             patch.object(m, "ownership_paths", return_value=["/unknown/editor.desktop"]), \
             contextlib.redirect_stderr(io.StringIO()):
            apps, targets = m.inventory(entries, errors)
        self.assertIsNone(apps["editor"]["installed"])
        self.assertIsNone(apps["editor"]["latest"])
        self.assertEqual(apps["editor"]["manager"], "unknown")
        self.assertFalse(targets)
        self.assertIn("pacman:ownership", errors)
        self.assertIn("flatpak:installed", errors)

    def test_main_streams_complete_snapshots_despite_source_failure(self):
        repo = m.Target("pacman", "editor", repo="extra")
        aur = m.Target("aur", "other-bin")
        apps = {"editor": {"installed": "1", "latest": None, "source": repo.source, "checked_at": None},
                "other": {"installed": "2", "latest": None, "source": aur.source, "checked_at": None}}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cache.json"
            output = io.StringIO()
            with patch.object(m, "cache_path", return_value=path), \
                 patch.object(m, "desktop_entries", return_value=[]), \
                 patch.object(m, "inventory", return_value=(apps, {repo.source: repo, aur.source: aur})), \
                 patch.object(m, "fresh_repos", side_effect=m.MetadataError("repo offline")), \
                 patch.object(m, "aur_versions", return_value={aur.source: "3"}), \
                 contextlib.redirect_stdout(output), contextlib.redirect_stderr(io.StringIO()):
                m.main()
            snapshots = [json.loads(line) for line in output.getvalue().splitlines()]
            self.assertEqual(snapshots[0], {"apps": {}, "refreshing": True})
            self.assertIsNone(snapshots[1]["apps"]["other"]["latest"])
            self.assertFalse(snapshots[-1]["refreshing"])
            self.assertEqual(snapshots[-1]["apps"]["other"]["latest"], "3")
            for snapshot in snapshots[1:]:
                self.assertEqual(set(snapshot["apps"]), {"editor", "other"})
            cached = json.loads(path.read_text())
            self.assertIn(repo.source, cached["errors"])
            self.assertNotIn(repo.source, cached["entries"])

    def test_fresh_cache_avoids_network(self):
        target = m.Target("aur", "app")
        apps = {"app": {"installed": "1", "source": target.source}}
        cache = {"version": 1, "entries": {target.source: {"latest": "2", "checked_at": 990}}, "errors": {}}
        with patch.object(m, "time") as clock, patch.object(m, "load_cache", return_value=cache), \
             patch.object(m, "save_cache"), patch.object(m, "desktop_entries", return_value=[]), \
             patch.object(m, "inventory", return_value=(apps, {target.source: target})), \
             patch.object(m, "aur_versions") as refresh, contextlib.redirect_stdout(io.StringIO()):
            clock.time.return_value = 1000
            m.main()
        refresh.assert_not_called()
        self.assertEqual(apps["app"]["latest"], "2")

    def test_package_metadata_uses_exact_dates_and_size(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory) / "local/editor-2"
            package.mkdir(parents=True)
            (package / "desc").write_text(
                "%NAME%\neditor\n\n%SIZE%\n12345\n\n%INSTALLDATE%\n1000\n\n"
                "%BUILDDATE%\n900\n\n%INSTALLED_DB%\ntesting\n")
            with patch.object(m, "run", return_value=directory):
                metadata = m.package_metadata()["editor"]
            self.assertEqual(metadata, {"size_bytes": 12345, "installed_at": 1000,
                                        "built_at": 900, "repo": "testing"})

    def test_flatpak_date_is_commit_date_not_release_or_install_date(self):
        target = m.Target("flatpak", "org.App", installation="system", origin="flathub",
                          arch="x86_64", branch="stable")
        info = f"Ref: {target.ref}\nOrigin: flathub\nCommit: abc\nDate: 2026-08-21 16:07:31 +0000\n"
        with patch.object(m, "run", side_effect=[info, "12345\n"]):
            details, commit = m.flatpak_details(target)
        self.assertEqual(commit, "abc")
        self.assertEqual(details["size_bytes"], 12345)
        self.assertIsInstance(details["committed_at"], float)
        self.assertNotIn("installed_at", details)
        self.assertNotIn("released_at", details)

    def test_update_argv_is_data_and_never_executed(self):
        with patch.object(m, "run") as run, patch.object(m.shutil, "which", return_value="/usr/bin/paru"):
            self.assertEqual(m.update_command(m.Target("pacman", "editor", repo="extra")),
                             ["sudo", "pacman", "-Syu"])
            self.assertEqual(m.update_command(m.Target("aur", "editor-bin")), ["paru", "-Syu"])
            self.assertIsNone(m.update_command(None))
            run.assert_not_called()

    def test_force_refresh_bypasses_fresh_cache(self):
        target = m.Target("aur", "app")
        apps = {"app": {"installed": "1", "source": target.source}}
        cache = {"version": 1, "entries": {target.source: {"latest": "2", "checked_at": 990}}, "errors": {}}
        with patch.object(m, "time") as clock, patch.object(m, "load_cache", return_value=cache), \
             patch.object(m, "save_cache"), patch.object(m, "desktop_entries", return_value=[]), \
             patch.object(m, "inventory", return_value=(apps, {target.source: target})), \
             patch.object(m, "aur_versions", return_value={target.source: "3"}) as refresh, \
             contextlib.redirect_stdout(io.StringIO()):
            clock.time.return_value = 1000
            m.main(refresh=True)
        refresh.assert_called_once()
        self.assertEqual(apps["app"]["latest"], "3")

    def test_atomic_cache_and_corrupt_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cache.json"
            path.write_text("{broken")
            self.assertEqual(m.load_cache(path)["entries"], {})
            cache = {"version": 1, "entries": {}, "errors": {"aur:app": {"message": "offline", "at": 1}}}
            m.save_cache(path, cache)
            self.assertEqual(m.load_cache(path), cache)
            self.assertEqual(list(Path(directory).iterdir()), [path])


if __name__ == "__main__":
    unittest.main()
