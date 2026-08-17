pragma Singleton
import Quickshell
import QtQuick

Singleton {
    id: root

    /**
     * @param { string } summary 
     * @param { string } appName 
     * @param { string } category 
     * @returns { string }
     */
    function findSuitableMaterialSymbol(summary = "", appName = "", category = "") {
        const defaultType = 'notifications';
        const combined = `${appName} ${summary} ${category}`.toLowerCase().trim();
        if (combined.length === 0) return defaultType;

        const keywordsToTypes = {
            'recorder': 'screen_record',
            'recording': 'screen_record',
            'screen record': 'screen_record',
            'chat': 'chat',
            'message': 'chat',
            'whatsapp': 'chat',
            'ami-ai': 'smart_toy',
            'discord': 'forum',
            'telegram': 'send',
            'slack': 'workspaces',
            'element': 'forum',
            'zulip': 'chat',
            'reboot': 'restart_alt',
            'restart': 'restart_alt',
            'record': 'screen_record',
            'screencast': 'screen_record',
            'battery': 'battery_alert',
            'power': 'power',
            'screenshot': 'screenshot_monitor',
            'screen snip': 'screenshot_monitor',
            'welcome': 'waving_hand',
            'time': 'schedule',
            'timer': 'timer',
            'installed': 'download_done',
            'downloaded': 'download_done',
            'downloading': 'downloading',
            'download': 'download',
            'upload': 'upload',
            'configuration reloaded': 'reset_wrench',
            'unable': 'error',
            'error': 'error',
            'fail': 'error',
            'warning': 'warning',
            'alert': 'notification_important',
            'critical': 'warning',
            "couldn't": 'help',
            'config': 'tune',
            'update': 'system_update',
            'upgrade': 'system_update_alt',
            'ai response': 'neurology',
            'control': 'settings',
            'settings': 'settings',
            'upsca': 'compare',
            'music': 'music_note',
            'spotify': 'music_note',
            'playing': 'play_circle',
            'install': 'deployed_code_update',
            'input': 'keyboard_alt',
            'preedit': 'keyboard_alt',
            'mail': 'mail',
            'email': 'mail',
            'thunderbird': 'mail',
            'calendar': 'event',
            'meeting': 'event',
            'bluetooth': 'bluetooth',
            'wifi': 'wifi',
            'network': 'lan',
            'security': 'security',
            'shield': 'shield',
            'copy': 'content_copy',
            'clipboard': 'content_paste',
            'github': 'code',
            'gitlab': 'code',
            'terminal': 'terminal',
            'startswith:file': 'folder_copy',
        };

        for (const [keyword, type] of Object.entries(keywordsToTypes)) {
            if (keyword.startsWith('startswith:')) {
                const startsWithKeyword = keyword.replace('startswith:', '');
                if (combined.startsWith(startsWithKeyword)) {
                    return type;
                }
            } else if (combined.includes(keyword)) {
                return type;
            }
        }

        return defaultType;
    }

    /**
     * Checks if the app is a system daemon / background utility (should not have a "Buka App" button)
     * @param { string } appName
     * @returns { boolean }
     */
    function isSystemDaemon(appName = "") {
        const lower = (appName || "").toLowerCase().trim();
        if (!lower || lower === "notification" || lower === "other" || lower === "system") return true;
        const daemons = [
            "recorder", "gpu-screen-recorder", "screen snip", "screenshot", "screen recorder",
            "system alert", "power", "battery", "network", "volume", "osd", "quickshell",
            "hyprland", "daemon", "service", "cron", "polkit", "auth", "clipboard", "snip"
        ];
        return daemons.some(d => lower.includes(d));
    }

    /**
     * Determines whether a detected path is a folder, image, video, or general file
     * @param { string } rawPath
     * @returns { string } "folder" | "image" | "video" | "audio" | "file" | ""
     */
    function getPathType(rawPath = "") {
        if (!rawPath) return "";
        const clean = rawPath.replace(/^file:\/\//, "").trim();
        if (clean.length === 0) return "";

        const lower = clean.toLowerCase();
        
        // Image extensions
        if (/\.(png|jpe?g|webp|svg|gif|bmp|avif)$/i.test(lower)) return "image";
        
        // Video extensions
        if (/\.(mp4|webm|mkv|avi|mov|flv|wmv|m4v)$/i.test(lower)) return "video";
        
        // Audio extensions
        if (/\.(mp3|flac|wav|ogg|m4a|opus|aac)$/i.test(lower)) return "audio";
        
        // Has a generic file extension (e.g. .pdf, .zip, .txt, .json, .tar.gz, .iso, .deb, etc.)
        if (/\.[a-zA-Z0-9]{1,6}$/i.test(lower)) return "file";
        
        // Otherwise, it is a directory / folder (e.g. /home/nakumi/Video, /home/nakumi/Downloads)
        return "folder";
    }

    /**
     * Detects if the notification is from a messaging or chat conversation
     * @param { string } appName
     * @param { string } summary
     * @param { string } body
     * @param { string } category
     * @returns { boolean }
     */
    function isMessagingNotification(appName = "", summary = "", body = "", category = "") {
        const lowerApp = (appName || "").toLowerCase();
        const lowerCat = (category || "").toLowerCase();
        const lowerSum = (summary || "").toLowerCase();

        if (lowerCat.includes("im.received") || lowerCat.includes("chat") || lowerCat.includes("message")) return true;
        
        const chatApps = [
            "whatsapp", "telegram", "discord", "slack", "signal", "element", "zulip",
            "messenger", "wechat", "line", "skype", "teams", "viber", "messages", "sms",
            "ami-ai", "chat", "matrix", "vesktop", "zapzap", "ferdium", "rambox", "session"
        ];
        if (chatApps.some(app => lowerApp.includes(app))) return true;
        
        if ((lowerApp === "notification" || lowerApp === "other" || lowerApp === "") && summary && summary.length > 0 && summary.length < 30) {
            if (!lowerSum.includes("screenshot") && !lowerSum.includes("download") && !lowerSum.includes("alert") && !lowerSum.includes("warning") && !lowerSum.includes("suhu") && !lowerSum.includes("cpu") && !lowerSum.includes("record")) {
                return true;
            }
        }

        return false;
    }

    /**
     * Extracts OTP / 4-8 digit verification code if present in text
     * @param { string } text
     * @returns { string }
     */
    function extractOtpCode(text = "") {
        if (!text) return "";
        const otpMatch = text.match(/(?:code|kode|otp|pin|verifikasi|verification)\s*(?:is|:|\s)\s*([0-9]{4,8})/i);
        if (otpMatch && otpMatch[1]) return otpMatch[1];
        return "";
    }

    /**
     * @param { string } text
     * @returns { string }
     */
    function extractFilePath(text) {
        if (!text) return "";
        const match = text.match(/(?:(?:\/[\w\.\-]+)+|(?:~\/[\w\.\-]+)+)/);
        if (match && match[0] && match[0].length > 3) {
            return match[0];
        }
        return "";
    }

    /**
     * @param { string } text
     * @returns { string }
     */
    function extractUrl(text) {
        if (!text) return "";
        const match = text.match(/https?:\/\/[^\s<>"']+/);
        if (match && match[0]) {
            return match[0];
        }
        return "";
    }

    /**
     * Attempts to focus the app window in Hyprland, or launch it if not open
     * @param { string } appName
     * @param { string } desktopEntry
     */
    function focusOrLaunchApp(appName = "", desktopEntry = "") {
        if (!appName && !desktopEntry) return;
        if (isSystemDaemon(appName)) return;
        const target = (desktopEntry || appName).toLowerCase().replace(".desktop", "");
        
        const focusCmd = `
            CLIENTS=$(hyprctl clients -j 2>/dev/null)
            MATCH=$(echo "$CLIENTS" | jq -r --arg t "${target}" '.[] | select((.class|ascii_downcase|contains($t)) or (.title|ascii_downcase|contains($t)) or (.initialClass|ascii_downcase|contains($t))) | .address' | head -n 1)
            
            if [ -z "$MATCH" ] || [ "$MATCH" = "null" ]; then
                if [[ "${target}" =~ (whatsapp|zapzap) ]]; then
                    MATCH=$(echo "$CLIENTS" | jq -r '.[] | select((.class|ascii_downcase|contains("whatsapp")) or (.class|ascii_downcase|contains("zapzap"))) | .address' | head -n 1)
                elif [[ "${target}" =~ (telegram) ]]; then
                    MATCH=$(echo "$CLIENTS" | jq -r '.[] | select((.class|ascii_downcase|contains("telegram"))) | .address' | head -n 1)
                elif [[ "${target}" =~ (discord|vesktop) ]]; then
                    MATCH=$(echo "$CLIENTS" | jq -r '.[] | select((.class|ascii_downcase|contains("discord")) or (.class|ascii_downcase|contains("vesktop"))) | .address' | head -n 1)
                fi
            fi

            if [ -n "$MATCH" ] && [ "$MATCH" != "null" ]; then
                hyprctl dispatch focuswindow "address:$MATCH"
            else
                if command -v gtk-launch &>/dev/null && [ -n "${desktopEntry}" ]; then
                    gtk-launch "${desktopEntry}" 2>/dev/null || gtk-launch "${target}" 2>/dev/null || (${target} & disown)
                else
                    (${target} & disown) 2>/dev/null || xdg-open "${target}" 2>/dev/null
                fi
            fi
        `;
        Quickshell.execDetached(["bash", "-c", focusCmd]);
    }

    /**
     * @param { number | string | Date } timestamp 
     * @returns { string }
     */
    function getFriendlyNotifTimeString(timestamp) {
        if (!timestamp) return '';
        const messageTime = new Date(timestamp);
        const now = new Date();
        const diffMs = Math.max(0, now.getTime() - messageTime.getTime());

        if (diffMs < 60000)
            return 'Just now';

        if (messageTime.toDateString() === now.toDateString()) {
            const diffMinutes = Math.floor(diffMs / 60000);
            const diffHours = Math.floor(diffMs / 3600000);

            if (diffHours > 0) {
                return `${diffHours}h ago`;
            } else {
                return `${diffMinutes}m ago`;
            }
        }

        if (messageTime.toDateString() === new Date(now.getTime() - 86400000).toDateString())
            return 'Yesterday';

        return Qt.formatDateTime(messageTime, "MMM dd, hh:mm");
    }

    /**
     * @param { string } body
     * @param { string } appName
     * @returns { string }
     */
    function processNotificationBody(body, appName) {
        if (!body) return "";
        let processedBody = body;
        
        if (appName) {
            const lowerApp = appName.toLowerCase();
            const chromiumBrowsers = [
                "brave", "chrome", "chromium", "vivaldi", "opera", "microsoft edge"
            ];

            if (chromiumBrowsers.some(name => lowerApp.includes(name))) {
                const lines = body.split('\n\n');
                if (lines.length > 1 && lines[0].startsWith('<a')) {
                    processedBody = lines.slice(1).join('\n\n');
                }
            }
        }

        processedBody = processedBody.replace(/<img/gi, '\n\n<img');
        return processedBody;
    }
}
