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
        Log.app.info("TedCat launched")
    }

    /// Never lose a recording on quit: stop it, wait for the file, then exit.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let recording = captureController?.recording, recording.isBusy else {
            return .terminateNow
        }
        recording.finish {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        captureController?.stop()
    }
}
