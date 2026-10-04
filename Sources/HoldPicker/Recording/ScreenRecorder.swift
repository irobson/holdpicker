import AVFoundation
import CoreMedia
import HoldPickerCore
import ScreenCaptureKit

/// Records one screen region, plus system audio, to an MP4 file.
///
/// Pipeline: `SCStream` delivers BGRA frames and PCM audio as `CMSampleBuffer`s
/// on a private serial queue; they are appended directly to an `AVAssetWriter`
/// that encodes HEVC video and AAC audio in real time. Nothing is buffered in
/// memory beyond what the encoder needs.
///
/// All mutable state is touched only on `queue`, hence `@unchecked Sendable`.
final class ScreenRecorder: NSObject, @unchecked Sendable {
    enum Error: Swift.Error, LocalizedError {
        case regionTooSmall
        case writerUnavailable(String)
        case noFramesCaptured

        var errorDescription: String? {
            switch self {
            case .regionTooSmall:
                return "The selected region is too small to record."
            case .writerUnavailable(let reason):
                return "Could not create the video file: \(reason)"
            case .noFramesCaptured:
                return "No video frames were captured."
            }
        }
    }

    struct Options {
        var capturesSystemAudio = true
        var showsCursor = true
    }

    let outputURL: URL
    /// Called on the main queue if the stream stops on its own (display
    /// unplugged, permission revoked). The recorder must then be stopped.
    var onUnexpectedStop: (@MainActor (Swift.Error) -> Void)?

    private let queue = DispatchQueue(label: "dev.holdpicker.recorder", qos: .userInitiated)
    private var stream: SCStream!
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?

    private var sessionStart: CMTime?
    /// Host clock minus stream clock, measured at the first frame. Lets `finalize`
    /// express "now" in the stream's timeline without assuming both clocks match.
    private var clockOffset: CMTime = .zero
    private var lastVideoBuffer: CMSampleBuffer?
    private var isFinishing = false
    private var reportedWriterFailure = false

    // MARK: - Lifecycle

    /// Creates the stream and writer and starts capturing.
    static func start(
        rect: CGRect,
        displayID: CGDirectDisplayID,
        outputURL: URL,
        options: Options
    ) async throws -> ScreenRecorder {
        let (filter, display) = try await CaptureFilter.display(displayID)
        let scale = CGFloat(filter.pointPixelScale)

        guard let plan = VideoEncodingPlan(pointSize: rect.size, scale: scale) else {
            throw Error.regionTooSmall
        }

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CaptureFilter.sourceRect(for: rect, on: display)
        configuration.width = plan.pixelWidth
        configuration.height = plan.pixelHeight
        configuration.scalesToFit = false
        configuration.captureResolution = .best
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(VideoEncodingPlan.framesPerSecond))
        configuration.queueDepth = 6
        configuration.showsCursor = options.showsCursor
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB

        configuration.capturesAudio = options.capturesSystemAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2

        let recorder = try ScreenRecorder(
            filter: filter,
            configuration: configuration,
            plan: plan,
            outputURL: outputURL,
            capturesAudio: options.capturesSystemAudio
        )
        do {
            try await recorder.stream.startCapture()
        } catch {
            recorder.discardOutput()
            throw error
        }
        Log.recording.info("Recording \(plan.pixelWidth)×\(plan.pixelHeight) px @ \(plan.averageBitrate / 1000) kbps")
        return recorder
    }

    private init(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration,
        plan: VideoEncodingPlan,
        outputURL: URL,
        capturesAudio: Bool
    ) throws {
        self.outputURL = outputURL

        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw Error.writerUnavailable(error.localizedDescription)
        }
        // Puts the index at the start of the file so players can start instantly.
        writer.shouldOptimizeForNetworkUse = true

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: plan.pixelWidth,
            AVVideoHeightKey: plan.pixelHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: plan.averageBitrate,
                AVVideoExpectedSourceFrameRateKey: VideoEncodingPlan.framesPerSecond,
                AVVideoMaxKeyFrameIntervalKey: VideoEncodingPlan.framesPerSecond * 2,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = true

        if capturesAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ])
            input.expectsMediaDataInRealTime = true
            audioInput = input
        } else {
            audioInput = nil
        }

        guard writer.canAdd(videoInput) else { throw Error.writerUnavailable("video input rejected") }
        writer.add(videoInput)
        if let audioInput {
            guard writer.canAdd(audioInput) else { throw Error.writerUnavailable("audio input rejected") }
            writer.add(audioInput)
        }
        super.init()
        // The delegate reports unexpected stops, so the stream is created after `self` exists.
        stream = SCStream(filter: filter, configuration: configuration, delegate: self)

        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if capturesAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }

        // `startWriting` creates the file on disk, so it comes last: nothing
        // after it in `init` can throw and leave an empty file behind.
        guard writer.startWriting() else {
            throw Error.writerUnavailable(writer.error?.localizedDescription ?? "unknown error")
        }
    }

    /// Deletes the output file of a recording that never got going.
    private func discardOutput() {
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: outputURL)
    }

    /// Stops capturing and finalizes the file. Returns the file URL on success.
    func stop() async throws -> URL {
        do {
            try await stream.stopCapture()
        } catch {
            // The stream may already be stopped (unexpected stop path). Finalize anyway.
            Log.recording.debug("stopCapture: \(error.localizedDescription, privacy: .public)")
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                finalize { result in continuation.resume(with: result) }
            }
        }
    }

    // MARK: - Writing (on `queue`)

    private func finalize(completion: @escaping (Result<URL, Swift.Error>) -> Void) {
        isFinishing = true

        guard sessionStart != nil else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            completion(.failure(Error.noFramesCaptured))
            return
        }

        // ScreenCaptureKit only sends frames when pixels change. If the screen
        // was still at the end, repeat the last frame at "now" so the video
        // track lasts as long as the audio and the recording the user saw.
        let endTime = CMClockGetTime(CMClockGetHostTimeClock()) - clockOffset
        if let last = lastVideoBuffer,
           endTime > last.presentationTimeStamp,
           let tail = Self.retimed(last, to: endTime),
           videoInput.isReadyForMoreMediaData {
            videoInput.append(tail)
        }

        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        writer.endSession(atSourceTime: endTime)

        let writer = writer
        let url = outputURL
        writer.finishWriting {
            if writer.status == .completed {
                completion(.success(url))
            } else {
                // A failed MP4 is unplayable; do not leave it in the user's folder.
                try? FileManager.default.removeItem(at: url)
                completion(.failure(writer.error ?? Error.writerUnavailable("finishing failed")))
            }
        }
        lastVideoBuffer = nil
    }

    private func appendVideo(_ buffer: CMSampleBuffer) {
        guard Self.isCompleteFrame(buffer) else { return }

        let time = buffer.presentationTimeStamp
        if sessionStart == nil {
            writer.startSession(atSourceTime: time)
            sessionStart = time
            clockOffset = CMClockGetTime(CMClockGetHostTimeClock()) - time
        }
        if videoInput.isReadyForMoreMediaData {
            videoInput.append(buffer)
            lastVideoBuffer = buffer
        }
    }

    private func appendAudio(_ buffer: CMSampleBuffer) {
        guard let audioInput, let sessionStart,
              buffer.presentationTimeStamp >= sessionStart,
              audioInput.isReadyForMoreMediaData
        else { return }
        audioInput.append(buffer)
    }

    /// ScreenCaptureKit also emits idle/blank status buffers without pixels.
    private static func isCompleteFrame(_ buffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw)
        else { return false }
        return status == .complete
    }

    private static func retimed(_ buffer: CMSampleBuffer, to time: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var copy: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: buffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &copy
        )
        return copy
    }
}

// MARK: - SCStreamOutput, SCStreamDelegate

extension ScreenRecorder: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // A writer that fails mid-recording (disk full, encoder error) would
        // otherwise drop every buffer silently while the UI keeps counting.
        if writer.status == .failed, !reportedWriterFailure, !isFinishing {
            reportedWriterFailure = true
            let error = writer.error ?? Error.writerUnavailable("the video writer failed")
            Log.recording.error("Writer failed: \(error.localizedDescription, privacy: .public)")
            reportUnexpectedStop(error)
            return
        }
        guard !isFinishing, sampleBuffer.isValid, writer.status == .writing else { return }
        switch type {
        case .screen:
            appendVideo(sampleBuffer)
        case .audio:
            appendAudio(sampleBuffer)
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Swift.Error) {
        Log.recording.error("Stream stopped: \(error.localizedDescription, privacy: .public)")
        reportUnexpectedStop(error)
    }

    private func reportUnexpectedStop(_ error: Swift.Error) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.onUnexpectedStop?(error)
            }
        }
    }
}
