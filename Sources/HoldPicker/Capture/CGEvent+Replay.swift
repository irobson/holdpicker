import CoreGraphics

extension CGEvent {
    /// Written into `eventSourceUserData` on every event HoldPicker injects, so the
    /// tap can recognise its own events and let them through untouched.
    /// Real HID events carry `0` here.
    private static let syntheticMarker: Int64 = 0x484F_4C44 // "HOLD"

    var isSynthetic: Bool {
        getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker
    }

    /// Re-injects a copy of this event at the HID level, marked as synthetic.
    ///
    /// The copy keeps location, flags, click count and every other field, so
    /// the receiving app sees exactly what the user did, only a few
    /// milliseconds later.
    func replay() {
        guard let copy = copy() else { return }
        copy.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        copy.post(tap: .cghidEventTap)
    }
}
