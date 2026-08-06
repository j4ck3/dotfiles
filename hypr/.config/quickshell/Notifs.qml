pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Shared notification server + snapshot history for dashboard.
Singleton {
    id: root

    property var history: []
    readonly property int historyCap: 40

    NotificationServer {
        id: notifServer
        keepOnReload: true
        actionsSupported: true
        actionIconsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        inlineReplySupported: true
        persistenceSupported: true

        onNotification: notif => {
            notif.tracked = true
            if (!notif.transient)
                root.pushHistory(notif)
        }
    }

    readonly property NotificationServer server: notifServer

    function pushHistory(notif: var): void {
        const entry = {
            uid: `${notif.id}-${Date.now()}`,
            id: notif.id,
            appName: notif.appName || "",
            summary: notif.summary || "",
            body: notif.body || "",
            appIcon: notif.appIcon || "",
            image: notif.image ? String(notif.image) : "",
            time: Date.now(),
            urgency: (() => {
                try {
                    return notif.urgency
                } catch (e) {
                    return 1
                }
            })()
        }
        const next = [entry, ...root.history]
        root.history = next.slice(0, root.historyCap)
    }

    function removeHistory(uid: string): void {
        root.history = root.history.filter(e => e.uid !== uid)
    }

    function clearHistory(): void {
        root.history = []
    }

    function dismissTracked(id: int): void {
        const tracked = notifServer.trackedNotifications.values
        for (let i = 0; i < tracked.length; i++) {
            if (tracked[i].id === id) {
                tracked[i].dismiss()
                break
            }
        }
    }

    function dismissAllTracked(): void {
        const tracked = [...notifServer.trackedNotifications.values]
        for (let i = 0; i < tracked.length; i++)
            tracked[i].dismiss()
    }
}
