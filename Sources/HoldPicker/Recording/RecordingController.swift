import AppKit

/// Owns one recording at a time: the recorder, the frame around the region
/// and the floating stop control.
@MainActor
final class RecordingController {
    enum State: Equatable {
        case idle
        case starting
        case recording(since: Date)
        case saving
    }

    private let preferences: Preferences
    private var recorder: ScreenRecorder?
    private var frameWindow: RecordingFrameWindow?
    private var hud: RecordingHUD?

    private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((State) -> Void)?

    /// True from the moment a recording is requested until its file is written.
    var isBusy: Bool { state != .idle }

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    // MARK: - Start

    /// - Parameters:
    ///   - rect: Region in global CG coordinates.
    ///   - screen: The screen the region lives on.
    func start(rect: CGRect, on screen: NSScreen) {
        guard state == .idle else { return }
        state = .starting

        let displayID = ScreenGeometry.displayID(of: screen)
        let url: URL
        do {
            url = try RecordingStorage.newFileURL(in: preferences.recordingsFolder)
        } catch {
            fail(error)
            return
        }

        let options = ScreenRecorder.Options(capturesSystemAudio: preferences.recordsSystemAudio, showsCursor: true)

        Task { @MainActor in
            do {
                let recorder = try await ScreenRecorder.start(
                    rect: rect,
                    displayID: displayID,
                    outputURL: url,
                    options: options
                )
                recorder.onUnexpectedStop = { [weak self] _ in self?.stop() }
                self.recorder = recorder
                self.didStart(rect: rect, on: screen)
            } catch {
                self.fail(error)
            }
        }
    }

    private func didStart(rect: CGRect, on screen: NSScreen) {
        let startDate = Date()

        let frame = RecordingFrameWindow(cgRect: rect)
        frame.show()
        frameWindow = frame

        let hud = RecordingHUD(avoiding: ScreenGeometry.cocoaRect(fromCG: rect), on: screen)
        hud.onStop = { [weak self] in self?.stop() }
        hud.showRecording(since: startDate)
        self.hud = hud

        // Publish the state last: observers (the quit handler) may call
        // `stop()` synchronously and expect the windows to exist.
        state = .recording(since: startDate)

        playSound("Tink")
    }

    // MARK: - Stop

    func stop() {
        guard case .recording = state, let recorder else { return }
        state = .saving
        self.recorder = nil

        frameWindow?.dismiss()
        frameWindow = nil
        hud?.showSaving()
        playSound("Pop")

        Task { @MainActor in
            do {
                let url = try await recorder.stop()
                Log.recording.info("Saved \(url.lastPathComponent, privacy: .public)")
                hud?.showSaved(url)
            } catch {
                Log.recording.error("Saving failed: \(error.localizedDescription, privacy: .public)")
                hud?.showFailure(error.localizedDescription)
            }
            hud = nil
            state = .idle
        }
    }

    /// Stops and saves whatever is in flight, then calls `completion` once idle.
    /// Used on quit so a recording is never lost.
    func finish(completion: @escaping () -> Void) {
        guard isBusy else {
            completion()
            return
        }
        let previous = onStateChange
        onStateChange = { [weak self] newState in
            previous?(newState)
            switch newState {
            case .recording:
                // Quit arrived while the stream was still starting.
                self?.stop()
            case .idle:
                self?.onStateChange = previous
                completion()
            case .starting, .saving:
                break
            }
        }
        if case .recording = state {
            stop()
        }
    }

    // MARK: - Helpers

    private func fail(_ error: Error) {
        Log.recording.error("Could not start recording: \(error.localizedDescription, privacy: .public)")
        RecordingHUD.flashFailure(error.localizedDescription)
        state = .idle
    }

    private func playSound(_ name: String) {
        guard preferences.playsSound else { return }
        NSSound(named: name)?.play()
    }
}

/// Where recordings go and how they are named.
enum RecordingStorage {
    static var defaultFolder: URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        return movies.appendingPathComponent("HoldPicker", isDirectory: true)
    }

    /// `HoldPicker 2026-10-04 at 14.03.22.mp4`, matching macOS screenshot naming.
    static func newFileURL(in folder: URL, date: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "HoldPicker \(formatter.string(from: date))"

        var url = folder.appendingPathComponent(base).appendingPathExtension("mp4")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) (\(counter))").appendingPathExtension("mp4")
            counter += 1
        }
        return url
    }
}
