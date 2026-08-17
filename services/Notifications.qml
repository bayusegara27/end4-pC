pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

/**
 * Provides extra features not in Quickshell.Services.Notifications:
 *  - Persistent storage
 *  - Popup notifications, with timeout and hover pause
 *  - Notification groups by app
 *  - Inline replies & rich hints (progress, desktopEntry, category, image-path)
 *  - Click-to-activate (default action invocation)
 */
Singleton {
	id: root
    component Notif: QtObject {
        id: wrapper
        required property int notificationId
        property Notification notification
        property list<var> actions: notification?.actions.map((action) => ({
            "identifier": action.identifier,
            "text": action.text,
        })) ?? []
        property bool popup: false
        property bool isTransient: notification?.hints.transient ?? false
        property string appIcon: notification?.appIcon ?? ""
        property string appName: notification?.appName ?? ""
        property string body: notification?.body ?? ""
        property string image: {
            if (!notification) return "";
            if (notification.image && notification.image !== "") return notification.image;
            if (notification.hints) {
                if (notification.hints["image-path"]) return notification.hints["image-path"];
                if (notification.hints["image_path"]) return notification.hints["image_path"];
                if (notification.hints["image-data"]) return notification.hints["image-data"];
            }
            return "";
        }
        property string summary: notification?.summary ?? ""
        property double time
        property string urgency: notification?.urgency.toString() ?? "normal"
        property bool hasInlineReply: notification?.hasInlineReply ?? false
        property int progress: {
            if (!notification || !notification.hints) return -1;
            const val = notification.hints["value"] ?? notification.hints["progress"] ?? -1;
            return typeof val === "number" ? val : (parseInt(val) || -1);
        }
        property string desktopEntry: notification?.hints ? (notification.hints["desktop-entry"] || notification.hints["x-kde-display-appname"] || "") : ""
        property string category: notification?.hints ? (notification.hints["category"] || "") : ""
        property int expireTimeout: notification?.expireTimeout ?? 7000
        property bool timerPaused: false
        property Timer timer

        onNotificationChanged: {
            if (notification === null) {
                root.discardNotification(notificationId);
            }
        }
    }

    function notifToJSON(notif) {
        return {
            "notificationId": notif.notificationId,
            "actions": notif.actions,
            "appIcon": notif.appIcon,
            "appName": notif.appName,
            "body": notif.body,
            "image": notif.image,
            "summary": notif.summary,
            "time": notif.time,
            "urgency": notif.urgency,
            "progress": notif.progress,
            "category": notif.category,
            "desktopEntry": notif.desktopEntry,
        }
    }
    function notifToString(notif) {
        return JSON.stringify(notifToJSON(notif), null, 2);
    }

    component NotifTimer: Timer {
        required property int notificationId
        interval: 7000
        running: true
        onTriggered: () => {
            const index = root.list.findIndex((notif) => notif.notificationId === notificationId);
            const notifObject = root.list[index];
            if (notifObject && notifObject.timerPaused) {
                restart();
                return;
            }
            print("[Notifications] Notification timer triggered for ID: " + notificationId + ", transient: " + notifObject?.isTransient);
            if (notifObject && notifObject.isTransient) root.discardNotification(notificationId);
            else root.timeoutNotification(notificationId);
            destroy();
        }
    }

    property bool silent: false
    property int unread: 0
    property var filePath: Directories.notificationsPath
    property list<Notif> list: []
    property var popupList: list.filter((notif) => notif.popup);
    property bool popupInhibited: (GlobalStates?.sidebarRightOpen ?? false) || silent
    property var latestTimeForApp: ({})
    Component {
        id: notifComponent
        Notif {}
    }
    Component {
        id: notifTimerComponent
        NotifTimer {}
    }

    function stringifyList(list) {
        return JSON.stringify(list.map((notif) => notifToJSON(notif)), null, 2);
    }
    
    onListChanged: {
        // Automatically sync unread with remaining items
        if (root.list.length === 0) {
            root.unread = 0;
        } else if (root.unread > root.list.length) {
            root.unread = root.list.length;
        }

        // Update latest time for each app
        root.list.forEach((notif) => {
            if (!root.latestTimeForApp[notif.appName] || notif.time > root.latestTimeForApp[notif.appName]) {
                root.latestTimeForApp[notif.appName] = Math.max(root.latestTimeForApp[notif.appName] || 0, notif.time);
            }
        });
        // Remove apps that no longer have notifications
        Object.keys(root.latestTimeForApp).forEach((appName) => {
            if (!root.list.some((notif) => notif.appName === appName)) {
                delete root.latestTimeForApp[appName];
            }
        });
    }

    function appNameListForGroups(groups) {
        return Object.keys(groups).sort((a, b) => {
            return groups[b].time - groups[a].time;
        });
    }

    function groupsForList(list) {
        const groups = {};
        list.forEach((notif) => {
            if (!groups[notif.appName]) {
                groups[notif.appName] = {
                    appName: notif.appName,
                    appIcon: notif.appIcon,
                    notifications: [],
                    time: 0
                };
            }
            groups[notif.appName].notifications.push(notif);
            // Always set to the latest time in the group
            groups[notif.appName].time = latestTimeForApp[notif.appName] || notif.time;
        });
        return groups;
    }

    property var groupsByAppName: groupsForList(root.list)
    property var popupGroupsByAppName: groupsForList(root.popupList)
    property list<string> appNameList: appNameListForGroups(root.groupsByAppName)
    property list<string> popupAppNameList: appNameListForGroups(root.popupGroupsByAppName)

    // Quickshell's notification IDs starts at 1 on each run, while saved notifications
    // can already contain higher IDs. This is for avoiding id collisions
    property int idOffset
    signal initDone();
    signal notify(notification: var);
    signal discard(id: int);
    signal discardAll();
    signal timeout(id: var);

	NotificationServer {
        id: notifServer
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        inlineReplySupported: true
        keepOnReload: false
        persistenceSupported: true

        onNotification: (notification) => {
            notification.tracked = true
            const defaultTimeout = (Config?.options?.notifications?.timeout ?? 7000);
            const timeoutVal = (notification.expireTimeout && notification.expireTimeout > 0) ? notification.expireTimeout : defaultTimeout;
            
            const newNotifObject = notifComponent.createObject(root, {
                "notificationId": notification.id + root.idOffset,
                "notification": notification,
                "time": Date.now(),
                "expireTimeout": timeoutVal,
            });
			root.list = [...root.list, newNotifObject];

            // Popup
            if (!root.popupInhibited) {
                newNotifObject.popup = true;
                if (notification.expireTimeout !== 0) {
                    newNotifObject.timer = notifTimerComponent.createObject(root, {
                        "notificationId": newNotifObject.notificationId,
                        "interval": timeoutVal,
                    });
                }
                root.unread++;
            }
            root.notify(newNotifObject);
            notifFileView.setText(stringifyList(root.list));
        }
    }

    function markAllRead() {
        root.unread = 0;
    }

    function discardNotification(id) {
        console.log("[Notifications] Discarding notification with ID: " + id);
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        if (index !== -1) {
            root.list.splice(index, 1);
            if (root.unread > 0) {
                root.unread = Math.max(0, root.unread - 1);
            }
            notifFileView.setText(stringifyList(root.list));
            triggerListChange();
            root.discard(id);
        }
        if (notifServerIndex !== -1) {
            notifServer.trackedNotifications.values[notifServerIndex].dismiss();
        }
    }

    function discardAllNotifications() {
        console.log("[Notifications] Discarding all notifications");
        root.list.forEach((notif) => {
            const notifServerIndex = notifServer.trackedNotifications.values.findIndex((serverNotif) => serverNotif.id + root.idOffset === notif.notificationId);
            if (notifServerIndex !== -1) {
                notifServer.trackedNotifications.values[notifServerIndex].dismiss();
            }
            root.discard(notif.notificationId);
        });
        root.list = [];
        root.unread = 0;
        notifFileView.setText(stringifyList(root.list));
        triggerListChange();
        root.discardAll();
    }

    function discardAppGroup(appName) {
        console.log("[Notifications] Discarding all notifications for app: " + appName);
        const toRemove = root.list.filter(n => n.appName === appName).map(n => n.notificationId);
        toRemove.forEach(id => root.discardNotification(id));
    }

    function cancelTimeout(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null) {
            root.list[index].timerPaused = true;
            if (root.list[index].timer) root.list[index].timer.stop();
        }
    }

    function resumeTimeout(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null) {
            root.list[index].timerPaused = false;
            if (root.list[index].timer) root.list[index].timer.restart();
        }
    }

    function timeoutNotification(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null)
            root.list[index].popup = false;
        root.timeout(id);
    }

    function timeoutAll() {
        root.popupList.forEach((notif) => {
            root.timeout(notif.notificationId);
        })
        root.popupList.forEach((notif) => {
            notif.popup = false;
        });
    }

    function attemptInvokeAction(id, notifIdentifier) {
        console.log("[Notifications] Attempting to invoke action with identifier: " + notifIdentifier + " for notification ID: " + id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        if (notifServerIndex !== -1) {
            const notifServerNotif = notifServer.trackedNotifications.values[notifServerIndex];
            const action = notifServerNotif.actions.find((action) => action.identifier === notifIdentifier);
            if (action) {
                action.invoke();
            }
        } 
        else {
            console.log("Notification not found in server: " + id);
        }
        root.discardNotification(id);
    }

    function invokeDefaultAction(id) {
        console.log("[Notifications] Invoking default action for notification ID: " + id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        if (notifServerIndex !== -1) {
            const notifServerNotif = notifServer.trackedNotifications.values[notifServerIndex];
            const defaultAction = notifServerNotif.actions.find((action) => action.identifier === "default" || action.identifier === "0" || action.identifier === "activate");
            if (defaultAction) {
                defaultAction.invoke();
                root.discardNotification(id);
                return true;
            } else if (notifServerNotif.actions.length > 0) {
                notifServerNotif.actions[0].invoke();
                root.discardNotification(id);
                return true;
            }
        }
        return false;
    }

    function sendInlineReply(id, replyText) {
        console.log("[Notifications] Sending inline reply for notification ID: " + id + ", text: " + replyText);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        if (notifServerIndex !== -1) {
            const notifServerNotif = notifServer.trackedNotifications.values[notifServerIndex];
            if (notifServerNotif && typeof notifServerNotif.sendInlineReply === "function") {
                notifServerNotif.sendInlineReply(replyText);
            }
        }
        root.discardNotification(id);
    }

    function triggerListChange() {
        root.list = root.list.slice(0);
    }

    function refresh() {
        notifFileView.reload();
    }

    Component.onCompleted: {
        refresh();
    }

    FileView {
        id: notifFileView
        path: Qt.resolvedUrl(filePath)
        onLoaded: {
            const fileContents = notifFileView.text()
            root.list = JSON.parse(fileContents).map((notif) => {
                return notifComponent.createObject(root, {
                    "notificationId": notif.notificationId,
                    "actions": notif.actions || [],
                    "appIcon": notif.appIcon || "",
                    "appName": notif.appName || "",
                    "body": notif.body || "",
                    "image": notif.image || "",
                    "summary": notif.summary || "",
                    "time": notif.time || Date.now(),
                    "urgency": notif.urgency || "normal",
                    "progress": notif.progress !== undefined ? notif.progress : -1,
                    "category": notif.category || "",
                    "desktopEntry": notif.desktopEntry || "",
                });
            });
            // Find largest notificationId
            let maxId = 0
            root.list.forEach((notif) => {
                maxId = Math.max(maxId, notif.notificationId)
            })

            console.log("[Notifications] File loaded")
            root.idOffset = maxId
            root.initDone()
        }
        onLoadFailed: (error) => {
            if(error == FileViewError.FileNotFound) {
                console.log("[Notifications] File not found, creating new file.")
                root.list = []
                notifFileView.setText(stringifyList(root.list));
            } else {
                console.log("[Notifications] Error loading file: " + error)
            }
        }
    }
}
