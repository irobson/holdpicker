import AppKit
import ServiceManagement

/// Owns the menu bar item and its menu. All user-facing configuration lives here.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let captureController: CaptureController
    private let preferences: Preferences
    private let menu = NSMenu()

    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let soundItem = NSMenuItem(title: "Play Sound", action: #selector(toggleSound), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let triggerMenu = NSMenu()
    private let durationMenu = NSMenu()

    private struct TriggerOption { let title: String; let modifiers: CGEventFlags }
    private let triggerOptions: [TriggerOption] = [
        .init(title: "Hold only", modifiers: []),
        .init(title: "⌃ Control + Hold", modifiers: .maskControl),
        .init(title: "⌥ Option + Hold", modifiers: .maskAlternate),
        .init(title: "⇧ Shift + Hold", modifiers: .maskShift),
        .init(title: "⌘ Command + Hold", modifiers: .maskCommand),
    ]
    private let durationOptionsMs = [200, 350, 500, 750]

    init(captureController: CaptureController, preferences: Preferences) {
        self.captureController = captureController
        self.preferences = preferences
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "HoldShot")
            button.image?.isTemplate = true
        }

        buildMenu()
        statusItem.menu = menu

        captureController.onStatusChange = { [weak self] _ in self?.refresh() }
        refresh()
    }

    // MARK: - Menu construction

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        enabledItem.target = self
        menu.addItem(enabledItem)

        let triggerItem = NSMenuItem(title: "Trigger", action: nil, keyEquivalent: "")
        for option in triggerOptions {
            let item = NSMenuItem(title: option.title, action: #selector(selectTrigger(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(option.modifiers.rawValue)
            triggerMenu.addItem(item)
        }
        triggerItem.submenu = triggerMenu
        menu.addItem(triggerItem)

        let durationItem = NSMenuItem(title: "Hold Duration", action: nil, keyEquivalent: "")
        for ms in durationOptionsMs {
            let item = NSMenuItem(title: "\(ms) ms", action: #selector(selectHoldDuration(_:)), keyEquivalent: "")
            item.target = self
            item.tag = ms
            durationMenu.addItem(item)
        }
        durationItem.submenu = durationMenu
        menu.addItem(durationItem)

        soundItem.target = self
        menu.addItem(soundItem)

        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let accessibility = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibility), keyEquivalent: "")
        accessibility.target = self
        menu.addItem(accessibility)

        let screenRecording = NSMenuItem(title: "Open Screen Recording Settings…", action: #selector(openScreenRecording), keyEquivalent: "")
        screenRecording.target = self
        menu.addItem(screenRecording)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit HoldShot", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - State refresh

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
    }

    private func refresh() {
        switch captureController.status {
        case .active:
            statusLine.title = "HoldShot is active"
            statusItem.button?.appearsDisabled = false
        case .disabled:
            statusLine.title = "HoldShot is paused"
            statusItem.button?.appearsDisabled = true
        case .needsAccessibility:
            statusLine.title = "Waiting for Accessibility permission…"
            statusItem.button?.appearsDisabled = true
        }

        enabledItem.state = preferences.isEnabled ? .on : .off
        soundItem.state = preferences.playsSound ? .on : .off

        let required = preferences.requiredModifiers.rawValue
        for item in triggerMenu.items {
            item.state = UInt64(item.tag) == required ? .on : .off
        }

        let currentMs = Int((preferences.holdDuration * 1000).rounded())
        for item in durationMenu.items {
            item.state = item.tag == currentMs ? .on : .off
        }

        loginItem.isEnabled = LaunchAtLogin.isAvailable
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        preferences.isEnabled.toggle()
        captureController.setEnabled(preferences.isEnabled)
        refresh()
    }

    @objc private func selectTrigger(_ sender: NSMenuItem) {
        preferences.requiredModifiers = CGEventFlags(rawValue: UInt64(sender.tag))
        refresh()
    }

    @objc private func selectHoldDuration(_ sender: NSMenuItem) {
        preferences.holdDuration = Double(sender.tag) / 1000
        refresh()
    }

    @objc private func toggleSound() {
        preferences.playsSound.toggle()
        refresh()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.set(enabled: !LaunchAtLogin.isEnabled)
        } catch {
            Log.app.error("Launch at login failed: \(error.localizedDescription)")
        }
        refresh()
    }

    @objc private func openAccessibility() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func openScreenRecording() {
        Permissions.openScreenRecordingSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// Thin wrapper over `SMAppService`. Only works when running from an `.app` bundle.
private enum LaunchAtLogin {
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func set(enabled: Bool) throws {
        guard isAvailable else { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
