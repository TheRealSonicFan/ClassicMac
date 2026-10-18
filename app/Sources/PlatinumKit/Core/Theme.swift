import SwiftUI
import CoreGraphics

// The Platinum palette and metrics. One Mac pixel is one point: on a Retina
// display that is exactly two device pixels, so every edge lands on a device
// pixel and nothing is ever resampled (RetroBoot decision D013: integer
// scaling only). The values are RetroBoot's Mac OS 8.1 Platinum set, measured
// on screen in the user's M5Tab-Macintosh project (MIT, see platinum/README.md).
public enum Platinum {
    // MARK: Grays

    public static let black = RGB(0x000000)
    public static let white = RGB(0xFFFFFF)
    public static let gray3A = RGB(0x3A3A3A)
    public static let gray63 = RGB(0x636363)
    public static let gray73 = RGB(0x737373)
    public static let gray94 = RGB(0x949494)
    public static let grayA5 = RGB(0xA5A5A5)
    public static let grayB5 = RGB(0xB5B5B5)
    public static let grayC5 = RGB(0xC5C5C5)
    public static let grayCE = RGB(0xCECECE)
    public static let grayDE = RGB(0xDEDEDE)
    public static let grayE6 = RGB(0xE6E6E6)
    public static let grayF7 = RGB(0xF7F7F7)

    // MARK: Lavender (the default Appearance variation)

    public static let lavenderLight = RGB(0xDEDBFF)
    public static let lavender = RGB(0xB5B2FF)
    public static let lavenderShadow = RGB(0x8486DE)
    public static let lavenderDark = RGB(0x5255B5)

    // MARK: Roles

    /// Window frame and title bar.
    public static let frame = grayDE
    /// Dialog and window body, button faces.
    public static let face = grayE6
    /// List and text selection.
    public static let highlight = RGB(0xCCCCFF)
    /// A highlighted menu item.
    public static let menuHighlight = RGB(0x6363CE)
    /// Secondary detail text.
    public static let dimText = gray73
    /// Disabled text and glyphs.
    public static let disabledText = gray94
    /// Keyboard focus ring (inner and outer lines).
    public static let focusInner = RGB(0x6365CE)
    public static let focusOuter = RGB(0x9C9AEF)
    /// Error text.
    public static let errorText = RGB(0xCC0000)
    /// The Mac OS 8 desktop blue, used behind previews.
    public static let desktop = RGB(0x63639C)

    // MARK: Metrics (Mac pixels)

    public static let buttonHeight: CGFloat = 20
    public static let buttonMinWidth: CGFloat = 59
    public static let buttonGap: CGFloat = 12
    /// The default button's ring sits this far outside the button.
    public static let defaultRing: CGFloat = 3
    public static let checkboxSize: CGFloat = 12
    /// Box left edge to label for checkboxes and radio buttons.
    public static let checkLabelOffset: CGFloat = 18
    public static let popupHeight: CGFloat = 20
    public static let fieldHeight: CGFloat = 22
    public static let listRowHeight: CGFloat = 18
    public static let scrollbarWidth: CGFloat = 16
    public static let titleBarHeight: CGFloat = 19
    public static let progressHeight: CGFloat = 12
    /// Dialog content inset from the window frame.
    public static let dialogMargin: CGFloat = 12
}

/// A 24-bit color usable from CoreGraphics and SwiftUI.
public struct RGB: Hashable, Sendable {
    public let value: UInt32

    public init(_ value: UInt32) { self.value = value & 0xFFFFFF }

    public var red: CGFloat { CGFloat((value >> 16) & 0xFF) / 255 }
    public var green: CGFloat { CGFloat((value >> 8) & 0xFF) / 255 }
    public var blue: CGFloat { CGFloat(value & 0xFF) / 255 }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    public var color: Color {
        Color(.sRGB, red: Double(red), green: Double(green), blue: Double(blue), opacity: 1)
    }

    /// Linear blend toward another color, t in 0...n.
    public func mix(_ other: RGB, _ t: Int, _ n: Int) -> RGB {
        guard n > 0 else { return self }
        func channel(_ shift: UInt32) -> UInt32 {
            let a = Int((value >> shift) & 0xFF), b = Int((other.value >> shift) & 0xFF)
            return UInt32(a + (b - a) * t / n) << shift
        }
        return RGB(channel(16) | channel(8) | channel(0))
    }

    /// The disabled (grayed) version of a lavender color, as rbui draws it.
    public var dimmed: RGB {
        let r = Int((value >> 16) & 0xFF), g = Int((value >> 8) & 0xFF), b = Int(value & 0xFF)
        let v = ((r * 30 + g * 59 + b * 11) / 100 + 0xE6) / 2
        return RGB(UInt32(v << 16 | v << 8 | v))
    }
}

public extension Color {
    static func platinum(_ rgb: RGB) -> Color { rgb.color }
}
