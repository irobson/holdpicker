import Testing
import Foundation
@testable import HoldPickerCore

@Suite("HoldGestureRecognizer")
struct HoldGestureRecognizerTests {
    let origin = CGPoint(x: 100, y: 100)
    let shift = HoldGestureConfiguration.shiftModifier
    let control: UInt64 = 1 << 18

    private func makeRecognizer(modifiers: UInt64 = 0, allowsRecording: Bool = true) -> HoldGestureRecognizer {
        HoldGestureRecognizer(configuration: .init(
            holdDuration: 0.3,
            moveTolerance: 4,
            requiredModifiers: modifiers,
            allowsRecording: allowsRecording
        ))
    }

    @Test("A quick click is held, then replayed untouched")
    func quickClick() {
        let r = makeRecognizer()

        #expect(r.handle(.down(origin, modifiers: 0)) == Response(.hold, [.armTimer(0.3)]))
        #expect(r.state == .pending(origin: origin, mode: .screenshot))

        #expect(r.handle(.up(origin)) == Response(.release, [.disarmTimer]))
        #expect(r.state == .idle)
    }

    @Test("Moving past the tolerance turns the press into a normal drag")
    func dragBeforeTimeout() {
        let r = makeRecognizer()
        _ = r.handle(.down(origin, modifiers: 0))

        // Small jitter stays within tolerance and is swallowed.
        #expect(r.handle(.drag(CGPoint(x: 102, y: 101))) == Response(.swallow))
        #expect(r.state == .pending(origin: origin, mode: .screenshot))

        // Real movement releases the held mouse-down and hands control back.
        #expect(r.handle(.drag(CGPoint(x: 120, y: 100))) == Response(.release, [.disarmTimer]))
        #expect(r.state == .passthrough)

        #expect(r.handle(.drag(CGPoint(x: 140, y: 100))) == Response(.pass))
        #expect(r.handle(.up(CGPoint(x: 140, y: 100))) == Response(.pass))
        #expect(r.state == .idle)
    }

    @Test("Holding still until the timer fires starts a screenshot selection")
    func holdStartsSelection() {
        let r = makeRecognizer()
        _ = r.handle(.down(origin, modifiers: 0))

        #expect(r.handle(.holdTimeout) == Response(.swallow, [.beginSelection(origin: origin, mode: .screenshot)]))
        #expect(r.isSelecting)

        let corner = CGPoint(x: 50, y: 180)
        let expected = CGRect(x: 50, y: 100, width: 50, height: 80)
        #expect(r.handle(.drag(corner)) == Response(.swallow, [.updateSelection(expected)]))
        #expect(r.handle(.up(corner)) == Response(.swallow, [.commitSelection(expected, mode: .screenshot)]))
        #expect(r.state == .idle)
    }

    @Test("Shift + hold starts a recording selection")
    func shiftHoldStartsRecording() {
        let r = makeRecognizer()
        _ = r.handle(.down(origin, modifiers: shift))
        #expect(r.state == .pending(origin: origin, mode: .recording))

        #expect(r.handle(.holdTimeout) == Response(.swallow, [.beginSelection(origin: origin, mode: .recording)]))

        let corner = CGPoint(x: 300, y: 250)
        let expected = CGRect(x: 100, y: 100, width: 200, height: 150)
        #expect(r.handle(.up(corner)) == Response(.swallow, [.commitSelection(expected, mode: .recording)]))
    }

    @Test("A quick Shift-click still reaches the app (text selection, multi-select)")
    func shiftClickReplayed() {
        let r = makeRecognizer()
        #expect(r.handle(.down(origin, modifiers: shift)) == Response(.hold, [.armTimer(0.3)]))
        #expect(r.handle(.up(origin)) == Response(.release, [.disarmTimer]))
    }

    @Test("Shift + hold passes through while recording is not allowed")
    func recordingBlockedWhileBusy() {
        let r = makeRecognizer(allowsRecording: false)
        #expect(r.handle(.down(origin, modifiers: shift)) == Response(.pass))
        #expect(r.state == .idle)

        // Screenshots keep working during a recording.
        #expect(r.handle(.down(origin, modifiers: 0)) == Response(.hold, [.armTimer(0.3)]))
    }

    @Test("Recording combines with a required trigger modifier")
    func recordingWithTriggerModifier() {
        let r = makeRecognizer(modifiers: control)

        #expect(r.handle(.down(origin, modifiers: shift)) == Response(.pass))

        _ = r.handle(.down(origin, modifiers: control | shift))
        #expect(r.state == .pending(origin: origin, mode: .recording))
    }

    @Test("Escape cancels an active selection")
    func escapeCancels() {
        let r = makeRecognizer()
        _ = r.handle(.down(origin, modifiers: 0))
        _ = r.handle(.holdTimeout)

        #expect(r.handle(.cancel) == Response(.swallow, [.cancelSelection]))
        #expect(r.state == .idle)

        // The eventual mouse-up must not leak a stray click.
        #expect(r.handle(.up(origin)) == Response(.pass))
    }

    @Test("A late timeout after release is ignored")
    func lateTimeoutIgnored() {
        let r = makeRecognizer()
        _ = r.handle(.down(origin, modifiers: 0))
        _ = r.handle(.up(origin))

        #expect(r.handle(.holdTimeout) == Response(.pass))
        #expect(r.state == .idle)
    }

    @Test("Required modifiers gate the gesture")
    func requiredModifiers() {
        let r = makeRecognizer(modifiers: control)

        #expect(r.handle(.down(origin, modifiers: 0)) == Response(.pass))
        #expect(r.state == .idle)

        #expect(r.handle(.down(origin, modifiers: control)) == Response(.hold, [.armTimer(0.3)]))
        #expect(r.state == .pending(origin: origin, mode: .screenshot))
    }

    @Test("Rectangles are normalized regardless of drag direction")
    func rectNormalization() {
        let a = CGPoint(x: 10, y: 20)
        let b = CGPoint(x: 5, y: 40)
        #expect(CGRect(corner: a, opposite: b) == CGRect(x: 5, y: 20, width: 5, height: 20))
        #expect(CGRect(corner: b, opposite: a) == CGRect(x: 5, y: 20, width: 5, height: 20))
    }

    @Test("Clamping keeps the selection on screen")
    func clamping() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(CGRect(x: -10, y: 90, width: 30, height: 30).clamped(to: bounds) == CGRect(x: 0, y: 90, width: 20, height: 10))
        #expect(CGRect(x: 200, y: 200, width: 10, height: 10).clamped(to: bounds) == .zero)
    }
}
