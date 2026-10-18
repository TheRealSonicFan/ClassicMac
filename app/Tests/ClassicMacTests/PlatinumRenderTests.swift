import XCTest
import SwiftUI
import AppKit
@testable import PlatinumKit

/// Renders Platinum views to PNG for visual review when
/// PLATINUM_RENDER_DIR is set; otherwise checks they render at all.
@MainActor
final class PlatinumRenderTests: XCTestCase {
    func render<V: View>(_ view: V, name: String) throws -> CGImage {
        let renderer = ImageRenderer(content: view.environment(\.platinumStaticRender, true))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, "\(name) did not render")
        if let dir = ProcessInfo.processInfo.environment["PLATINUM_RENDER_DIR"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(dest, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(dest))
        }
        return image
    }

    func testFontsRegister() {
        PlatinumFonts.registerIfNeeded()
        for font in PlatinumFont.allCases {
            let ct = font.ctFont()
            XCTAssertEqual(CTFontCopyPostScriptName(ct) as String, font.rawValue)
        }
        XCTAssertEqual(PlatinumFonts.width("Mac OS", font: .system), PlatinumFonts.width("Mac OS", font: .system).rounded())
    }

    func testGalleryRenders() throws {
        let image = try render(PlatinumGalleryWindow(), name: "gallery")
        XCTAssertEqual(image.width, (656 + 13) * 2)
    }

    func testAlertRenders() throws {
        let alert = PlatinumAlert(icon: .caution, message: "Shut down “Mac OS 9.2.2 Deluxe”?",
                                  informative: "Mac OS shuts down first, as if you chose Shut Down from the Special menu. If it does not respond within 15 seconds, the Mac turns off and unsaved work may be lost.",
                                  buttons: [PlatinumAlertButton("Shut Down", role: .default),
                                            PlatinumAlertButton("Cancel", role: .cancel)]) {}
        let state = PlatinumWindowState(title: "")
        _ = try render(PlatinumWindowChrome(state: state, kind: .modal) { alert }.frame(width: 413, height: 150), name: "alert")
    }

    func testMenuRenders() throws {
        let items = [PlatinumMenu.Item(title: "640 x 480"), PlatinumMenu.Item(title: "800 x 600"),
                     PlatinumMenu.Item(title: "1024 x 768", checked: true), PlatinumMenu.Item(title: "", separator: true),
                     PlatinumMenu.Item(title: "Custom…", enabled: false)]
        let view = PlatinumMenu.MenuView(items: items)
        view.frame = NSRect(x: 0, y: 0, width: view.naturalWidth + 2, height: view.naturalHeight + 2)
        view.highlighted = 1
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        if let dir = ProcessInfo.processInfo.environment["PLATINUM_RENDER_DIR"] {
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("menu.png"))
        }
        XCTAssertEqual(view.item(at: NSPoint(x: 30, y: CGFloat(PlatinumMenu.topMargin + 16 + 4))), 1)
        XCTAssertNil(view.item(at: NSPoint(x: 30, y: CGFloat(PlatinumMenu.topMargin + 3 * 16 + 2))), "separators are not choosable")
    }
}
