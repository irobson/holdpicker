import AppKit

enum Clipboard {
    /// Replaces the general pasteboard with the image, as PNG and TIFF.
    ///
    /// `pointSize` is the on-screen size in points. Storing it on the bitmap
    /// keeps the DPI metadata correct, so a Retina capture pastes at its
    /// original size instead of twice as large.
    static func write(_ image: CGImage, pointSize: CGSize) {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = pointSize

        let item = NSPasteboardItem()
        if let png = rep.representation(using: .png, properties: [:]) {
            item.setData(png, forType: .png)
        }
        if let tiff = rep.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
}
