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
    private let soundItem = NSMenuItem(title: "Play Sounds", action: #selector(toggleSound), keyEquivalent: "")
    private let hintItems = (0..<2).map { _ in NSMenuItem(title: "", action: nil, keyEquivalent: "") }
    private let recordAudioItem = NSMenuItem(title: "Record Audio Only", action: #selector(recordAudioOnly), keyEquivalent: "")
    private var currentSymbol: String?
    private let stopRecordingItem = NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "")
    private let systemAudioItem = NSMenuItem(title: "Include System Audio in Videos", action: #selector(toggleSystemAudio), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let triggerMenu = NSMenu()
    private let durationMenu = NSMenu()

    private struct TriggerOption { let title: String; let modifiers: CGEventFlags }
    private let triggerOptions: [TriggerOption] = [
        .init(title: "Hold only", modifiers: []),
        .init(title: "⌃ Control + Hold", modifiers: .maskControl),
        .init(title: "⌥ Option + Hold", modifiers: .maskAlternate),
        .init(title: "⌘ Command + Hold", modifiers: .maskCommand),
    ]
    private let durationOptionsMs = [200, 350, 500, 750]

    init(captureController: CaptureController, preferences: Preferences) {
        self.captureController = captureController
        self.preferences = preferences
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.toolTip = "TedCat"
            button.image?.isTemplate = true
        }

        buildMenu()
        statusItem.menu = menu

        captureController.onStatusChange = { [weak self] _ in self?.refresh() }
        captureController.recording.onStateChange = { [weak self] _ in self?.refresh() }
        refresh()
    }

    // MARK: - Menu construction

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        statusLine.isEnabled = false
        menu.addItem(statusLine)

        for item in hintItems {
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())

        recordAudioItem.target = self
        menu.addItem(recordAudioItem)

        stopRecordingItem.target = self
        menu.addItem(stopRecordingItem)
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

        menu.addItem(.separator())

        systemAudioItem.target = self
        menu.addItem(systemAudioItem)

        let openFolder = NSMenuItem(title: "Open Recordings Folder", action: #selector(openRecordingsFolder), keyEquivalent: "")
        openFolder.target = self
        menu.addItem(openFolder)

        let chooseFolder = NSMenuItem(title: "Change Recordings Folder…", action: #selector(chooseRecordingsFolder), keyEquivalent: "")
        chooseFolder.target = self
        menu.addItem(chooseFolder)

        menu.addItem(.separator())

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

        let quit = NSMenuItem(title: "Quit TedCat", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - State refresh

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
    }

    private func refresh() {
        let recordingState = captureController.recording.state
        let isRecordingNow: Bool = { if case .recording = recordingState { return true } else { return false } }()
        stopRecordingItem.isHidden = !isRecordingNow
        recordAudioItem.isHidden = recordingState != .idle

        switch captureController.status {
        case .active:
            switch recordingState {
            case .recording: statusLine.title = "Recording…"
            case .starting: statusLine.title = "Starting recording…"
            case .saving: statusLine.title = "Saving recording…"
            case .idle: statusLine.title = "TedCat is active"
            }
            statusItem.button?.appearsDisabled = false
        case .disabled:
            statusLine.title = "TedCat is paused"
            statusItem.button?.appearsDisabled = true
        case .needsAccessibility:
            statusLine.title = "Waiting for Accessibility permission…"
            statusItem.button?.appearsDisabled = true
        }

        let isRecording = recordingState != .idle
        let iconKey = isRecording ? "recording" : "idle"
        if currentSymbol != iconKey {
            currentSymbol = iconKey
            statusItem.button?.image = StatusIcon.image(recording: isRecording)
        }

        for (item, line) in zip(hintItems, Self.gestureHints(for: preferences.requiredModifiers)) {
            item.title = line
        }

        enabledItem.state = preferences.isEnabled ? .on : .off
        systemAudioItem.state = preferences.recordsSystemAudio ? .on : .off
        soundItem.state = preferences.playsSound ? .on : .off

        let required = preferences.requiredModifiers.rawValue
        for item in triggerMenu.items {
            item.state = UInt64(item.tag) == required ? .on : .off
        }

        let currentMs = Int((preferences.holdDuration * 1000).rounded())
        for item in durationMenu.items {
            item.state = item.tag == currentMs ? .on : .off
        }

        let loginState = LaunchAtLogin.state
        switch loginState {
        case .unavailable:
            loginItem.title = "Launch at Login"
            loginItem.isEnabled = false
            loginItem.state = .off
        case .off, .on:
            loginItem.title = "Launch at Login"
            loginItem.isEnabled = true
            loginItem.state = loginState == .on ? .on : .off
        case .needsApproval:
            loginItem.title = "Launch at Login: Allow in Login Items…"
            loginItem.isEnabled = true
            loginItem.state = .mixed
        }
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

    @objc private func recordAudioOnly() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        captureController.recording.startAudioOnly(on: screen)
    }

    @objc private func stopRecording() {
        captureController.recording.stop()
    }

    @objc private func toggleSystemAudio() {
        preferences.recordsSystemAudio.toggle()
        refresh()
    }

    @objc private func openRecordingsFolder() {
        let folder = preferences.recordingsFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc private func chooseRecordingsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = preferences.recordingsFolder
        panel.prompt = "Use Folder"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            preferences.recordingsFolder = url
        }
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.set(enabled: LaunchAtLogin.state != .on)
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

extension StatusBarController {
    /// The two gestures, prefixed with the trigger modifier when one is set.
    static func gestureHints(for trigger: CGEventFlags) -> [String] {
        var prefix = ""
        if trigger.contains(.maskControl) { prefix += "⌃" }
        if trigger.contains(.maskAlternate) { prefix += "⌥" }
        if trigger.contains(.maskCommand) { prefix += "⌘" }
        let hold = prefix.isEmpty ? "Hold" : "\(prefix) + Hold"
        let recordHold = "\(prefix)⇧ + Hold"
        return [
            "\(hold), drag: screenshot to clipboard",
            "\(recordHold), drag: record video of the area",
        ]
    }
}

/// The menu bar glyph: Ted's silhouette from the app bundle.
///
/// - Idle: a template image, so macOS tints it for light and dark menu bars.
/// - Recording: the same silhouette drawn in the menu bar's text color with
///   the camera-lens eye filled in red, like the system's recording indicators.
///   Template images are single-color, so this one is drawn on demand and
///   resolves the color for the current appearance each time it is drawn.
///
/// Falls back to SF Symbols when the bundle has no artwork (under `swift run`).
enum StatusIcon {
    private static let pointSize = NSSize(width: 18, height: 18)

    /// The lens of Ted's camera eye in the MenuBarIcon master, as fractions of
    /// the image (origin bottom-left). Measured from the artwork: centre at
    /// (346, 279) px from the top-left of the 512 px master, ring edge at 47 px.
    private static let lensCenter = CGPoint(x: 346.4 / 512, y: 1 - 279.0 / 512)
    private static let lensRadius: CGFloat = 47.0 / 512

    static func image(recording: Bool) -> NSImage? {
        let label = recording ? "TedCat, recording" : "TedCat"
        guard let artwork = NSImage(named: "MenuBarIcon") else {
            let symbol = recording ? "record.circle" : "camera.viewfinder"
            let fallback = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            fallback?.isTemplate = true
            return fallback
        }

        guard recording else {
            let idle = artwork.copy() as! NSImage
            idle.size = pointSize
            idle.isTemplate = true
            idle.accessibilityDescription = label
            return idle
        }

        let image = NSImage(size: pointSize, flipped: false) { rect in
            // Silhouette in the menu bar's text color for the current appearance.
            artwork.draw(in: rect)
            NSColor.labelColor.set()
            rect.fill(using: .sourceAtop)

            // Red lens.
            let radius = lensRadius * rect.width
            let center = CGPoint(x: rect.minX + lensCenter.x * rect.width, y: rect.minY + lensCenter.y * rect.height)
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = label
        return image
    }
}

/// Thin wrapper over `SMAppService`. Only works when running from an `.app` bundle.
@MainActor
private enum LaunchAtLogin {
    enum State {
        /// Not running from a bundle (`swift run`): the option is unavailable.
        case unavailable
        case off
        case on
        /// Registered, but switched off under System Settings › General ›
        /// Login Items. Only the user can turn it back on there.
        case needsApproval
    }

    static var state: State {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        default: return .off
        }
    }

    /// Turns the option on or off. Failures are shown, not just logged; when
    /// macOS needs the user's approval, the Login Items settings open.
    static func set(enabled: Bool) {
        switch state {
        case .unavailable:
            return
        case .needsApproval:
            // register() would fail, and unregister() would undo the user's
            // choice in System Settings: let them decide there.
            SMAppService.openSystemSettingsLoginItems()
            return
        case .on, .off:
            break
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let nsError = error as NSError
            Log.app.error("Launch at login failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public): \(nsError.localizedDescription, privacy: .public)")
            if nsError.code == kSMErrorLaunchDeniedByUser {
                SMAppService.openSystemSettingsLoginItems()
                return
            }
            let alert = NSAlert()
            alert.messageText = enabled ? "TedCat could not be added to Login Items" : "TedCat could not be removed from Login Items"
            alert.informativeText = nsError.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Open Login Items")
            NSApp.activate()
            if alert.runModal() == .alertSecondButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }
}
