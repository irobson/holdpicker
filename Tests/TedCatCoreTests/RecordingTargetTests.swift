import Testing
import Foundation
@testable import TedCatCore

@Suite("RecordingTarget")
struct RecordingTargetTests {
    @Test("Releasing without dragging records nothing (audio is menu-only)")
    func noDragIsTooSmall() {
        let press = CGRect(x: 100, y: 100, width: 0, height: 0)
        #expect(RecordingTarget(selection: press, scale: 2) == .tooSmall)
        #expect(RecordingTarget(selection: CGRect(x: 100, y: 100, width: 9, height: 9), scale: 2) == .tooSmall)
        #expect(RecordingTarget.isUndragged(press))
    }

    @Test("A real drag films the region")
    func dragIsRegion() {
        let rect = CGRect(x: 10, y: 20, width: 400, height: 300)
        #expect(RecordingTarget(selection: rect, scale: 2) == .region(rect))
        #expect(RecordingTarget(selection: rect, scale: 1) == .region(rect))
        #expect(!RecordingTarget.isUndragged(rect))
    }

    @Test("A thin or straight-line drag is too small to film")
    func thinDragIsTooSmall() {
        #expect(RecordingTarget(selection: CGRect(x: 0, y: 0, width: 200, height: 4), scale: 2) == .tooSmall)
        #expect(RecordingTarget(selection: CGRect(x: 0, y: 0, width: 200, height: 0), scale: 2) == .tooSmall)
        #expect(RecordingTarget(selection: CGRect(x: 0, y: 0, width: 200, height: 20), scale: 2) == .region(CGRect(x: 0, y: 0, width: 200, height: 20)))
    }

    @Test("The minimum filmable size depends on the display scale")
    func scaleMatters() {
        let rect = CGRect(x: 0, y: 0, width: 20, height: 20)
        #expect(RecordingTarget(selection: rect, scale: 2) == .region(rect))
        #expect(RecordingTarget(selection: rect, scale: 1) == .tooSmall)
    }

    @Test("The gesture never produces an audio-only recording")
    func gestureNeverAudio() {
        for size in [CGSize.zero, CGSize(width: 5, height: 5), CGSize(width: 9.5, height: 0)] {
            #expect(!RecordingTarget(selection: CGRect(origin: .zero, size: size), scale: 2).isAudioOnly)
        }
    }
}
