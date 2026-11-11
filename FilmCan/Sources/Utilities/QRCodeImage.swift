import AppKit
import CoreImage

/// QR code rendering with CoreImage (no dependency).
enum QRCodeImage {
    /// Modules as a bitmap, one pixel per module, before scaling. `nil` for empty text.
    static func ciImage(for text: String) -> CIImage? {
        guard !text.isEmpty, let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        return filter.outputImage
    }

    /// Crisp black-on-white image about `side` points wide (integer module scale).
    static func image(for text: String, side: CGFloat = 220) -> NSImage? {
        guard let modules = ciImage(for: text), modules.extent.width > 0 else { return nil }
        let scale = max(1, (side / modules.extent.width).rounded(.down))
        let scaled = modules.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
