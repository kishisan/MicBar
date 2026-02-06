import AppKit

final class ProcessResolver {
    private static let knownMicApps: [String: String] = [
        // Video conferencing
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams": "Microsoft Teams",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.apple.FaceTime": "FaceTime",
        "com.google.Chrome": "Google Chrome",
        "com.google.Chrome.canary": "Chrome Canary",
        "org.chromium.Chromium": "Chromium",
        "com.brave.Browser": "Brave",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.operasoftware.Opera": "Opera",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "org.mozilla.firefox": "Firefox",
        "org.mozilla.nightly": "Firefox Nightly",
        "com.apple.Safari": "Safari",
        "com.cisco.webexmeetingsapp": "Webex",
        "com.webex.meetingmanager": "Webex",

        // Communication
        "com.hnc.Discord": "Discord",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.skype.skype": "Skype",
        "org.whispersystems.signal-desktop": "Signal",
        "com.telegram.desktop": "Telegram",

        // Recording / Streaming
        "com.apple.QuickTimePlayerX": "QuickTime Player",
        "com.apple.garageband": "GarageBand",
        "com.apple.Logic10": "Logic Pro",
        "com.audacityteam.audacity": "Audacity",
        "com.obsproject.obs-studio": "OBS Studio",
        "com.elgato.StreamDeck": "Stream Deck",

        // Voice assistants / System
        "com.apple.assistant_service": "Siri/Dictation",
        "com.apple.Siri": "Siri",
    ]

    static func resolveActiveApp() -> String? {
        let runningApps = NSWorkspace.shared.runningApplications
        let runningBundleIDs = Set(runningApps.compactMap { $0.bundleIdentifier })

        for (bundleID, appName) in knownMicApps {
            if runningBundleIDs.contains(bundleID) {
                return appName
            }
        }

        return nil
    }
}
