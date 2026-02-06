import AppKit

final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var durationTimer: Timer?
    private var currentState = MicState(isActive: false, deviceName: nil, activeSince: nil)

    private let durationMenuItemTag = 999
    private let settings = SettingsManager.shared

    override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        updateDisplay()
    }

    func update(state: MicState) {
        currentState = state
        updateDisplay()
        rebuildStatusSection()

        if state.isActive {
            startDurationTimer()
        } else {
            stopDurationTimer()
        }
    }

    // MARK: - Display

    private func updateDisplay() {
        guard let button = statusItem.button else { return }

        let style = settings.displayStyle

        switch style {
        case .textOnly:
            button.image = nil
            button.attributedTitle = makeTitle()

        case .iconAndText:
            button.image = makeIcon()
            button.imagePosition = .imageLeading
            button.attributedTitle = makeTitle()

        case .iconOnly:
            button.attributedTitle = NSAttributedString(string: "")
            button.image = makeIcon()
            button.imagePosition = .imageOnly
        }
    }

    private func makeTitle() -> NSAttributedString {
        if currentState.isActive {
            return NSAttributedString(
                string: " \u{25CF} REC",
                attributes: [
                    .foregroundColor: NSColor.systemRed,
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
                ]
            )
        } else {
            return NSAttributedString(
                string: "MIC",
                attributes: [
                    .foregroundColor: NSColor.systemGray,
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                ]
            )
        }
    }

    private func makeIcon() -> NSImage? {
        let symbolName = currentState.isActive ? "mic.fill" : "mic"
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Microphone")
        else { return nil }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let configured = image.withSymbolConfiguration(config) ?? image

        configured.isTemplate = !currentState.isActive
        return configured
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        // Status section (placeholder, rebuilt on state change)
        let statusItem = NSMenuItem(title: "Microphone: Inactive", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        // Display Style submenu
        let styleMenu = NSMenu()
        for style in DisplayStyle.allCases {
            let item = NSMenuItem(
                title: style.label,
                action: #selector(changeDisplayStyle(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = style.rawValue
            item.state = style == settings.displayStyle ? .on : .off
            styleMenu.addItem(item)
        }
        let styleItem = NSMenuItem(title: "Display Style", action: nil, keyEquivalent: "")
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

        // Launch at Login
        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = settings.launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        // About
        let aboutItem = NSMenuItem(
            title: "About MicBar",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit MicBar",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem.menu = menu
    }

    private func rebuildStatusSection() {
        guard let menu = statusItem.menu else { return }

        // Remove old status items (everything before first separator)
        while let first = menu.items.first, !first.isSeparatorItem {
            menu.removeItem(at: 0)
        }

        var insertIndex = 0

        if currentState.isActive {
            let statusLine = NSMenuItem(
                title: "Microphone: Active", action: nil, keyEquivalent: "")
            statusLine.isEnabled = false
            menu.insertItem(statusLine, at: insertIndex)
            insertIndex += 1

            if let deviceName = currentState.deviceName {
                let deviceLine = NSMenuItem(
                    title: "  Device: \(deviceName)", action: nil, keyEquivalent: "")
                deviceLine.isEnabled = false
                menu.insertItem(deviceLine, at: insertIndex)
                insertIndex += 1
            }

            if let appName = ProcessResolver.resolveActiveApp() {
                let appLine = NSMenuItem(
                    title: "  Possibly: \(appName)", action: nil, keyEquivalent: "")
                appLine.isEnabled = false
                menu.insertItem(appLine, at: insertIndex)
                insertIndex += 1
            }

            let durationLine = NSMenuItem(title: "  Duration: 0s", action: nil, keyEquivalent: "")
            durationLine.isEnabled = false
            durationLine.tag = durationMenuItemTag
            menu.insertItem(durationLine, at: insertIndex)
            updateDurationMenuItem()

        } else {
            let statusLine = NSMenuItem(
                title: "Microphone: Inactive", action: nil, keyEquivalent: "")
            statusLine.isEnabled = false
            menu.insertItem(statusLine, at: insertIndex)
        }
    }

    // MARK: - Duration Timer

    private func startDurationTimer() {
        stopDurationTimer()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in
            self?.updateDurationMenuItem()
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func updateDurationMenuItem() {
        guard let menu = statusItem.menu,
            let item = menu.item(withTag: durationMenuItemTag),
            let since = currentState.activeSince
        else { return }

        let elapsed = Int(Date().timeIntervalSince(since))
        item.title = "  Duration: \(TimeFormatter.format(seconds: elapsed))"
    }

    // MARK: - Actions

    @objc private func changeDisplayStyle(_ sender: NSMenuItem) {
        guard let style = DisplayStyle(rawValue: sender.tag) else { return }
        settings.displayStyle = style
        updateDisplay()

        // Update checkmarks
        if let styleMenu = sender.menu {
            for item in styleMenu.items {
                item.state = item.tag == style.rawValue ? .on : .off
            }
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let newValue = !settings.launchAtLogin
        settings.launchAtLogin = newValue
        sender.state = newValue ? .on : .off

        LaunchAtLoginManager.setEnabled(newValue)
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "MicBar"
        alert.informativeText =
            "Version 1.0.0\n\nA lightweight macOS menu bar app that shows microphone usage status.\n\nhttps://github.com/kishisan/MicBar"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
