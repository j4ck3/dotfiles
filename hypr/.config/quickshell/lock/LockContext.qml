import QtQuick
import Quickshell
import Quickshell.Services.Pam

Scope {
    id: root

    signal unlocked()
    signal failed()

    // Shared across all lock surfaces (multi-monitor).
    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false

    onCurrentTextChanged: showFailure = false

    function reset(): void {
        currentText = ""
        unlockInProgress = false
        showFailure = false
        if (pam.active)
            pam.abort()
    }

    function tryUnlock(): void {
        if (currentText.length === 0 || unlockInProgress)
            return
        unlockInProgress = true
        if (!pam.start()) {
            unlockInProgress = false
            showFailure = true
            failed()
        }
    }

    PamContext {
        id: pam

        // Relative to this file: lock/pam/password.conf
        configDirectory: "pam"
        config: "password.conf"

        onPamMessage: {
            // Never respond with an empty password — pam_unix can mis-handle it.
            if (responseRequired) {
                if (root.currentText.length === 0) {
                    abort()
                    root.unlockInProgress = false
                    root.showFailure = true
                    root.failed()
                    return
                }
                respond(root.currentText)
            }
        }

        onCompleted: result => {
            if (result == PamResult.Success) {
                root.unlocked()
            } else {
                root.currentText = ""
                root.showFailure = true
                root.failed()
            }
            root.unlockInProgress = false
        }

        onError: _error => {
            root.currentText = ""
            root.unlockInProgress = false
            root.showFailure = true
            root.failed()
        }
    }
}
