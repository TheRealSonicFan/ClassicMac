import SwiftUI
import CoreGraphics
import CoreText

/// Integer-pixel drawing on a y-down CoreGraphics context, one Mac pixel per
/// unit. Every primitive fills whole pixels, so the result is identical at 1x
/// and exact at any integer device scale.
public struct PixelPainter {
    public let cg: CGContext

    public init(_ cg: CGContext) {
        self.cg = cg
        cg.setShouldAntialias(false)
        cg.interpolationQuality = .none
    }

    public func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: RGB) {
        guard w > 0, h > 0 else { return }
        cg.setFillColor(color.cgColor)
        cg.fill(CGRect(x: x, y: y, width: w, height: h))
    }

    public func fill(_ r: PixelRect, _ color: RGB) { fill(r.x, r.y, r.w, r.h, color) }

    public func hline(_ x: Int, _ y: Int, _ w: Int, _ color: RGB) { fill(x, y, w, 1, color) }
    public func vline(_ x: Int, _ y: Int, _ h: Int, _ color: RGB) { fill(x, y, 1, h, color) }
    public func pixel(_ x: Int, _ y: Int, _ color: RGB) { fill(x, y, 1, 1, color) }

    /// A one-pixel outline just inside r.
    public func frame(_ r: PixelRect, _ color: RGB) {
        guard r.w > 0, r.h > 0 else { return }
        hline(r.x, r.y, r.w, color)
        hline(r.x, r.y + r.h - 1, r.w, color)
        vline(r.x, r.y + 1, r.h - 2, color)
        vline(r.x + r.w - 1, r.y + 1, r.h - 2, color)
    }

    /// Blends a translucent black (alpha 0...1) over a pixel, for drop shadows.
    public func shade(_ x: Int, _ y: Int, _ w: Int, _ h: Int, alpha: CGFloat) {
        guard w > 0, h > 0 else { return }
        cg.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha))
        cg.fill(CGRect(x: x, y: y, width: w, height: h))
    }

    /// Draws rows of palette letters (see `PlatinumCode`); unknown letters
    /// and spaces are transparent. `map` lets a caller restyle colors for a
    /// state (pressed, disabled).
    public func coded(_ rows: [String], x: Int, y: Int, map: (RGB) -> RGB = { $0 }) {
        for (r, row) in rows.enumerated() {
            var c = 0
            for ch in row {
                if let color = PlatinumCode.color(ch) {
                    pixel(x + c, y + r, map(color))
                }
                c += 1
            }
        }
    }

    /// One line of text with its baseline at y.
    public func text(_ string: String, font: PlatinumFont, x: Int, baseline: Int, color: RGB, scale: Int = 1) {
        guard !string.isEmpty else { return }
        let attributed = NSAttributedString(string: string, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font.ctFont(scale: scale),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        cg.saveGState()
        cg.setShouldAntialias(true)
        cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        cg.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, cg)
        cg.restoreGState()
    }
}

/// An integer rectangle in Mac pixels.
public struct PixelRect: Hashable, Sendable {
    public var x: Int, y: Int, w: Int, h: Int

    public init(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }

    public init(size: CGSize) {
        self.init(0, 0, Int(size.width.rounded(.down)), Int(size.height.rounded(.down)))
    }

    public func inset(_ d: Int) -> PixelRect { PixelRect(x + d, y + d, w - 2 * d, h - 2 * d) }
    public func outset(_ d: Int) -> PixelRect { inset(-d) }
    public var isEmpty: Bool { w <= 0 || h <= 0 }
    public var maxX: Int { x + w }
    public var maxY: Int { y + h }
}

/// The single-letter color codes used by the measured control tables.
public enum PlatinumCode {
    public static func color(_ ch: Character) -> RGB? {
        switch ch {
        case "K": return Platinum.black
        case "W": return Platinum.white
        case "3": return Platinum.gray3A
        case "6": return Platinum.gray63
        case "7": return Platinum.gray73
        case "9": return Platinum.gray94
        case "A": return Platinum.grayA5
        case "B": return Platinum.grayB5
        case "C": return Platinum.grayC5
        case "c": return Platinum.grayCE
        case "D": return Platinum.grayDE
        case "E": return Platinum.grayE6
        case "F": return Platinum.grayF7
        case "l": return Platinum.lavenderLight
        case "a": return Platinum.lavender
        case "s": return Platinum.lavenderShadow
        case "d": return Platinum.lavenderDark
        default: return nil
        }
    }
}

/// A SwiftUI view that paints with a `PixelPainter` at one Mac pixel per point.
public struct PixelCanvas: View {
    private let draw: (PixelPainter, PixelRect) -> Void

    public init(_ draw: @escaping (PixelPainter, PixelRect) -> Void) {
        self.draw = draw
    }

    public var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            context.withCGContext { cg in
                draw(PixelPainter(cg), PixelRect(size: size))
            }
        }
    }
}
