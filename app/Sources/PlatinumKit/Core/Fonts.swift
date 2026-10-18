import SwiftUI
import CoreText
import CoreGraphics
import Foundation
#if os(macOS)
import AppKit
#endif

/// The Platinum bitmap fonts, compiled to pixel-square TrueType at build time
/// (platinum/tools/build_platinum_swift.py) and registered with Core Text for
/// this process. At their design size one font pixel is one point.
///
/// - System 12: the system font (emphasis, buttons, menus, titles, labels).
/// - Regular 12: body text, list details.
/// - Small 10: secondary and help text.
public enum PlatinumFont: String, CaseIterable, Sendable {
    case system = "PlatinumSystem"
    case regular = "PlatinumRegular"
    case regularBold = "PlatinumRegular-Bold"
    case small = "PlatinumSmall"
    case smallBold = "PlatinumSmall-Bold"

    /// Design size in points (= pixels per em).
    public var size: CGFloat {
        switch self {
        case .system, .regular, .regularBold: return 12
        case .small, .smallBold: return 10
        }
    }

    public var ascent: CGFloat { size == 12 ? 12 : 10 }
    public var descent: CGFloat { size == 12 ? 4 : 2 }
    public var lineHeight: CGFloat { ascent + descent }
    public var capHeight: CGFloat { size == 12 ? 9 : 7 }

    /// The SwiftUI font at its design size, or an integer multiple of it.
    public func font(scale: Int = 1) -> Font {
        Font(ctFont(scale: scale))
    }

    /// A Core Text font at its design size (or an integer multiple).
    public func ctFont(scale: Int = 1) -> CTFont {
        PlatinumFonts.font(self, size: size * CGFloat(max(1, scale)))
    }

    #if os(macOS)
    /// The AppKit font at its design size (toll-free bridged from Core Text).
    public func nsFont(scale: Int = 1) -> NSFont { ctFont(scale: scale) as NSFont }
    #endif
}

public extension Font {
    /// System 12: emphasis, buttons, labels, titles.
    static var platinumSystem: Font { PlatinumFont.system.font() }
    /// Regular 12: body text.
    static var platinumBody: Font { PlatinumFont.regular.font() }
    static var platinumBodyBold: Font { PlatinumFont.regularBold.font() }
    /// Small 10: secondary text.
    static var platinumSmall: Font { PlatinumFont.small.font() }
    static var platinumSmallBold: Font { PlatinumFont.smallBold.font() }
    /// System 12 at twice its size, pixel for pixel.
    static var platinumLarge: Font { PlatinumFont.system.font(scale: 2) }
}

public enum PlatinumFonts {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var descriptors: [String: CTFontDescriptor] = [:]
    nonisolated(unsafe) private static var fonts: [String: CTFont] = [:]

    /// Decodes the embedded fonts once per process. They are used directly as
    /// Core Text fonts, so nothing is registered system- or process-wide.
    public static func registerIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        loadLocked()
    }

    private static func loadLocked() {
        guard descriptors.isEmpty else { return }
        for data in PlatinumAssets.fonts {
            guard let bytes = Data(base64Encoded: data.base64),
                  let found = CTFontManagerCreateFontDescriptorsFromData(bytes as CFData) as? [CTFontDescriptor],
                  let descriptor = found.first else {
                assertionFailure("PlatinumKit: could not decode \(data.postScriptName)")
                continue
            }
            descriptors[data.postScriptName] = descriptor
        }
    }

    static func font(_ font: PlatinumFont, size: CGFloat) -> CTFont {
        lock.lock()
        defer { lock.unlock() }
        loadLocked()
        let key = "\(font.rawValue)@\(size)"
        if let cached = fonts[key] { return cached }
        let made: CTFont
        if let descriptor = descriptors[font.rawValue] {
            made = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        } else {
            made = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        }
        fonts[key] = made
        return made
    }

    /// Advance width of a string in the given font, in points.
    public static func width(_ text: String, font: PlatinumFont, scale: Int = 1) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font.ctFont(scale: scale)
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        return ceil(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
