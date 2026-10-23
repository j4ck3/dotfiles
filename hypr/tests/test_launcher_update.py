"""Update prompt tests; no package operations or applications are executed."""
import importlib.util
import io
from pathlib import Path
import subprocess
import unittest
from unittest.mock import MagicMock, patch

HELPER = Path(__file__).resolve().parents[1] / ".config/quickshell/scripts/launcher-update.py"
SPEC = importlib.util.spec_from_file_location("launcher_update", HELPER)
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)


class UpdateTests(unittest.TestCase):
    def test_enter_launches_selected_desktop_after_update(self):
        command = ["paru", "-S", "--", "editor-bin"]
        with patch.object(m.subprocess, "run", return_value=subprocess.CompletedProcess(command, 0)) as run, \
             patch.object(m, "start_prompt", return_value=True), patch.object(m, "launch_application") as launch:
            self.assertEqual(m.main("editor", command), 0)
        run.assert_called_once_with(command)
        launch.assert_called_once_with("editor")

    def test_escape_exits_without_launching(self):
        with patch.object(m.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)), \
             patch.object(m, "start_prompt", return_value=False), patch.object(m, "launch_application") as launch:
            self.assertEqual(m.main("editor", ["update"]), 0)
        launch.assert_not_called()

    def test_failed_update_does_not_offer_launch(self):
        with patch.object(m.subprocess, "run", return_value=subprocess.CompletedProcess([], 1)), \
             patch("builtins.input", return_value=""), patch.object(m, "start_prompt") as prompt:
            self.assertEqual(m.main("editor", ["update"]), 1)
        prompt.assert_not_called()

    def check_keys(self, keys, expected):
        stream = MagicMock()
        stream.isatty.return_value = True
        stream.fileno.return_value = 9
        stream.read.side_effect = keys
        with patch.object(m.sys, "stdin", stream), patch.object(m.termios, "tcgetattr", return_value=["original"]), \
             patch.object(m.tty, "setcbreak") as cbreak, patch.object(m.termios, "tcsetattr") as restore:
            self.assertEqual(m.start_prompt(), expected)
        cbreak.assert_called_once_with(9)
        restore.assert_called_once_with(9, m.termios.TCSADRAIN, ["original"])

    def test_enter_key(self):
        self.check_keys(["\n"], True)
        self.check_keys(["\r"], True)

    def test_escape_key(self):
        self.check_keys(["\x1b"], False)

    def test_other_keys_ignored(self):
        self.check_keys(["y", "n", "\n"], True)

    def test_eof_does_not_launch(self):
        self.check_keys([""], False)
        with patch.object(m.sys, "stdin", io.StringIO("\n")):
            self.assertFalse(m.start_prompt())

    def test_terminal_restored_on_read_failure(self):
        stream = MagicMock()
        stream.read.side_effect = KeyboardInterrupt
        with patch.object(m.sys, "stdin", stream), patch.object(m.termios, "tcgetattr", return_value=["original"]), \
             patch.object(m.tty, "setcbreak"), patch.object(m.termios, "tcsetattr") as restore:
            with self.assertRaises(KeyboardInterrupt):
                m.start_prompt()
        restore.assert_called_once()


if __name__ == "__main__":
    unittest.main()
