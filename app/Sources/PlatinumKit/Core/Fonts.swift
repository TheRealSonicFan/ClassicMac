import SwiftUI
import CoreText
import CoreGraphics
import Foundation

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
        PlatinumFonts.registerIfNeeded()
        return Font.custom(rawValue, fixedSize: size * CGFloat(max(1, scale)))
    }

    /// A Core Text font at its design size (or an integer multiple).
    public func ctFont(scale: Int = 1) -> CTFont {
        PlatinumFonts.registerIfNeeded()
        return CTFontCreateWithName(rawValue as CFString, size * CGFloat(max(1, scale)), nil)
    }
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
    nonisolated(unsafe) private static var registered = false

    /// Registers the embedded fonts once per process. Safe from any thread.
    public static func registerIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !registered else { return }
        registered = true
        for data in PlatinumAssets.fonts {
            guard let bytes = Data(base64Encoded: data.base64),
                  let provider = CGDataProvider(data: bytes as CFData),
                  let font = CGFont(provider) else {
                assertionFailure("PlatinumKit: could not decode \(data.postScriptName)")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterGraphicsFont(font, &error) {
                // Already registered (for example by a second bundle) is fine.
                error?.release()
            }
        }
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
