import XCTest
@testable import ClassicMac

final class ClassicIconTests: XCTestCase {
    func testStandardColorTables() {
        XCTAssertEqual(ClassicIcon.palette8.count, 256)
        XCTAssertEqual(ClassicIcon.palette8[0], 0xFFFFFF)
        XCTAssertEqual(ClassicIcon.palette8[1], 0xFFFFCC)
        XCTAssertEqual(ClassicIcon.palette8[214], 0x000033)
        XCTAssertEqual(ClassicIcon.palette8[215], 0xEE0000)
        XCTAssertEqual(ClassicIcon.palette8[245], 0xEEEEEE)
        XCTAssertEqual(ClassicIcon.palette8[255], 0x000000)
        XCTAssertEqual(ClassicIcon.palette4.count, 16)
    }

    /// An icl8 + ICN# family: masked pixels are transparent, the rest use the
    /// standard color table.
    func testDecodesMaskedEightBitIcon() throws {
        var icl8 = Data(repeating: 255, count: 1024)     // black
        icl8[0] = 0                                      // white top-left pixel
        var icnMask = Data(repeating: 0, count: 256)     // 128 icon + 128 mask bytes
        icnMask[128] = 0x80                              // only the first pixel visible
        func element(_ type: String, _ body: Data) -> Data {
            var d = Data(type.utf8)
            withUnsafeBytes(of: UInt32(body.count + 8).bigEndian) { d.append(contentsOf: $0) }
            return d + body
        }
        let members = element("ICN#", icnMask) + element("icl8", icl8)
        var icns = Data("icns".utf8)
        withUnsafeBytes(of: UInt32(members.count + 8).bigEndian) { icns.append(contentsOf: $0) }
        icns += members

        let image = try XCTUnwrap(ClassicIcon.decode(icns: icns)[32])
        XCTAssertEqual(image.width, 32)
        let pixels = try XCTUnwrap(image.dataProvider?.data as Data?)
        XCTAssertEqual(Array(pixels[0..<4]), [255, 255, 255, 255], "visible white pixel")
        XCTAssertEqual(Array(pixels[4..<8]), [0, 0, 0, 0], "masked pixel is transparent")
    }
}
