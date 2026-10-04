import AppKit
import ApplicationServices

/// The two macOS privacy grants TedCat depends on.
///
/// - Accessibility: required to create an *active* event tap, one that can
///   swallow and re-inject mouse events.
/// - Screen Recording: required by ScreenCaptureKit to read pixels.
enum Permissions {
    /// Returns whether the process is trusted for Accessibility.
    /// With `prompt: true`, macOS shows its standard "open System Settings" dialog once.
    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static var hasScreenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system Screen Recording prompt if not yet decided.
    @discardableResult
    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
