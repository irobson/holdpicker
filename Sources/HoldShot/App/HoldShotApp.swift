import AppKit

@main
@MainActor
enum HoldShotApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Menu bar only. Also applies when running unbundled via `swift run`.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
