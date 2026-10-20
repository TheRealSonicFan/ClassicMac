import SwiftUI
import PlatinumKit

/// What a Mac shows from power-on until Mac OS draws its own startup screen:
/// the classic 50 % gray checkerboard with a compact Mac whose screen holds a
/// Platinum progress bar. Firmware screens (black, OpenBIOS yellow) are never
/// shown.
///
/// The startup Mac is RetroBoot's original startup indicator art
/// (presenter/src/startup.c, MIT; no Apple bitmap copied or traced).
struct StartupCurtain: View {
    let started: Date
    /// The Mac's screen size, so the startup Mac stands where Mac OS draws
    /// its own (32 guest pixels, at the screen's whole-number scale).
    var screenSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let scale = screenSize.width > 0
                ? max(1, Int(min(geo.size.width / screenSize.width, geo.size.height / screenSize.height)))
                : 1
            ZStack {
                Checkerboard()
                TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { context in
                    StartupMac(progress: progress(at: context.date), scale: scale)
                }
            }
        }
        .accessibilityLabel("Starting up")
    }

    /// Mac OS takes about 20 seconds to draw; the bar eases toward 90 %.
    private func progress(at date: Date) -> Double {
        let t = max(0, date.timeIntervalSince(started))
        return 0.9 * (1 - exp(-t / 9))
    }
}

/// The one-pixel black and white checkerboard of a classic Mac's startup.
struct Checkerboard: View {
    private static let tile: CGImage = {
        let pixels: [UInt8] = [0, 0, 0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 0, 255]
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }()

    var body: some View {
        Image(decorative: Self.tile, scale: 1)
            .resizable(resizingMode: .tile)
            .interpolation(.none)
    }
}

/// RetroBoot's faceless compact Mac (32 x 32) with a progress bar in its
/// screen, at a whole-number scale.
struct StartupMac: View {
    let progress: Double
    var scale: Int = 1

    private static let art = [
        "....KKKKKKKKKKKKKKKKKKKKKKK.....",
        "...KWWWWWWWWWWWWWWWWWWWWWWcK....",
        "...KWcccccccccccccccccccccaK....",
        "...KWc6666666666666666666caK....",
        "...KWc6mmmmmmmmmmmmmmmmmWcaK....",
        "...KWc6mllllllllllllllllWcaK....",
        "...KWc6mllllllllllllllllWcaK....",
        "...KWc6mllllllllllllllllWcaK....",
        "...KWc6mllllllllllllllllWcaK....",
        "...KWc6mllllllllllllllllWcaK....",
        "...KWc6mllllllllllllllllWcaK....",
        "...KWc6mllllllllllllllllWcaK....",
        "...KWc6mllllllllllllllllWcaK....",
        "...KWc6mllllllllllllllllWcaK....",
        "...KWc6mllllllllllllllllWcaK....",
        "...KWc6mllllllllllllllllWcaK....",
        "...KWc6mllllllllllllllllWcaK....",
        "...KWc6WWWWWWWWWWWWWWWWWWcaK....",
        "...KWcccccccccccccccccccccaK....",
        "...KWcccccccccccccccccccccaK....",
        "...KWcccccccccccccccccccccaK....",
        "...KWccccccccc4444444444ccaK....",
        "...KWcggccccccWWWWWWWWWWccaK....",
        "...KWcccccccccccccccccccccaK....",
        "...KWcccccccccccccccccccccaK....",
        "...KWcccccccccccccccccccccaK....",
        "...KWaaaaaaaaaaaaaaaaaaaaaaK....",
        "....KKKKKKKKKKKKKKKKKKKKKKK.....",
        "....KaaaaaaaaaaaaaaaaaaaaaK.....",
        "....K777777777777777777777K.....",
        "....K555555555555555555555K.....",
        "....KKKKKKKKKKKKKKKKKKKKKKK.....",
    ]

    private static func color(_ ch: Character) -> RGB? {
        switch ch {
        case "K": return RGB(0x000000)
        case "W": return RGB(0xFFFFFF)
        case "c": return RGB(0xCCCCCC)
        case "a": return RGB(0x999999)
        case "6": return RGB(0x666666)
        case "m": return RGB(0xAAAADD)
        case "l": return RGB(0xCCCCFF)
        case "4": return RGB(0x444444)
        case "7": return RGB(0x777777)
        case "5": return RGB(0x555555)
        case "g": return RGB(0x00AA00)
        default: return nil
        }
    }

    var body: some View {
        PixelCanvas { p, _ in
            p.cg.saveGState()
            p.cg.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            for (y, row) in Self.art.enumerated() {
                for (x, ch) in row.enumerated() {
                    if let c = Self.color(ch) { p.pixel(x, y, c) }
                }
            }
            // The bar inside the screen: black frame, lavender fill over a light track.
            let bar = PixelRect(9, 9, 13, 5)
            p.frame(bar, Platinum.black)
            let inner = bar.inset(1)
            let filled = Int((Double(inner.w) * progress).rounded())
            for row in 0..<inner.h {
                let fill = row == 0 ? RGB(0xC6C4FF) : RGB(0xA5A3F7).mix(RGB(0x4A4DA5), row - 1, inner.h - 2)
                let track = row == 0 ? Platinum.grayA5 : Platinum.grayCE.mix(Platinum.grayF7, row - 1, inner.h - 2)
                p.hline(inner.x, inner.y + row, filled, fill)
                p.hline(inner.x + filled, inner.y + row, inner.w - filled, track)
            }
            p.cg.restoreGState()
        }
        .frame(width: CGFloat(32 * scale), height: CGFloat(32 * scale))
    }
}
