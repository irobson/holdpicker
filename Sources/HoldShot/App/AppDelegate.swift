import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences.shared
    private var captureController: CaptureController?
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let capture = CaptureController(preferences: preferences)
        captureController = capture
        statusBar = StatusBarController(captureController: capture, preferences: preferences)
        capture.start()
        Log.app.info("HoldShot launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        captureController?.stop()
    }
}
