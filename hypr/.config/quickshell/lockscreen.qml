//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import Quickshell
import Quickshell.Wayland
import "."
import "lock"

// DISABLED as the live lockscreen.
// quickshell 0.3.0 WlSessionLock + Hyprland 0.56 caused Wayland fatal errors
// (wl_display invalid object) and full session restarts.
// Live lock: hyprlock via Super+Ctrl+L / Power menu / hypridle.
//
// Do not wire binds to this file until QS session-lock is upgraded/fixed.
ShellRoot {
    LockContext {
        id: lockContext

        onUnlocked: {
            sessionLock.locked = false
            Qt.quit()
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: true

        WlSessionLockSurface {
            color: "#000000"

            LockSurface {
                anchors.fill: parent
                context: lockContext
            }
        }
    }
}
