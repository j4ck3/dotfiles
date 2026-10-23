#!/usr/bin/env python3
"""Run a selected package update, then offer to launch its desktop entry."""
import json
import subprocess
import sys
import termios
import tty


def launch_application(desktop_id):
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio
    try:
        gi.require_version("GioUnix", "2.0")
        from gi.repository import GioUnix
        desktop_type = GioUnix.DesktopAppInfo
    except (ValueError, ImportError):
        desktop_type = Gio.DesktopAppInfo
    entry = desktop_type.new(desktop_id if desktop_id.endswith(".desktop") else desktop_id + ".desktop")
    if not entry:
        raise RuntimeError("Application desktop entry no longer exists")
    # gio returns after dispatching the desktop entry. Disconnect terminal I/O
    # and session so closing this terminal does not terminate the application.
    subprocess.run(["gio", "launch", entry.get_filename()], check=True,
                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, start_new_session=True)


def main(desktop_id, command):
    if not isinstance(command, list) or not command or not all(isinstance(arg, str) for arg in command):
        raise ValueError("Expected an update argument array")
    result = subprocess.run(command)
    if result.returncode:
        print(f"\nUpdate failed (exit {result.returncode}). Application was not started.")
        try:
            input("Press Enter to close… ")
        except EOFError:
            pass
        return result.returncode
    if start_prompt():
        launch_application(desktop_id)
    return 0


def start_prompt():
    """Read Enter/Escape immediately, restoring terminal settings on every exit."""
    print("\nStart application? Enter: start · Esc: close", flush=True)
    if not sys.stdin.isatty():
        return False
    fd = sys.stdin.fileno()
    previous = termios.tcgetattr(fd)
    try:
        tty.setcbreak(fd)
        while True:
            key = sys.stdin.read(1)
            if key in ("\r", "\n"):
                return True
            if key in ("\x1b", ""):
                return False
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, previous)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1], json.loads(sys.argv[2])))
    except Exception as error:
        print(f"\n{error}", file=sys.stderr)
        try:
            input("Press Enter to close… ")
        except EOFError:
            pass
        sys.exit(1)
