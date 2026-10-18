import CoreGraphics

/// Interaction state of a control, as Platinum draws it.
public enum ControlState: Sendable {
    case normal, pressed, disabled
}

/// Pixel-exact Platinum control drawing.
///
/// Provenance (platinum/README.md): the window frame, title pinstripes, push
/// button and default ring edge tables, checkbox and radio sprites, group box,
/// edit field and list frames and the lavender scroll thumb were measured pixel
/// by pixel from Mac OS 8.1 in the user's M5Tab-Macintosh project and ported by
/// RetroBoot's rbui (presenter/ui/src/platinum.c, MIT). The pop-up, progress
/// bar, focus ring, menus and window boxes are original drawings in the same
/// palette.
public enum Chrome {

    // MARK: - Push buttons

    private struct EdgeRow {
        let left: String
        let fill: Character
        let right: String
    }

    private static let buttonTop: [EdgeRow] = [
        EdgeRow(left: "  3K", fill: "K", right: "K3  "),
        EdgeRow(left: " KcE", fill: "E", right: "EcK "),
        EdgeRow(left: "3cWW", fill: "W", right: "WEc3"),
        EdgeRow(left: "KEWW", fill: "E", right: "EC9K"),
    ]
    private static let buttonMiddle = EdgeRow(left: "KEWE", fill: "E", right: "EC9K")
    private static let buttonBottom: [EdgeRow] = [
        EdgeRow(left: "KEWE", fill: "E", right: "CC9K"),
        EdgeRow(left: "3cEC", fill: "C", right: "C993"),
        EdgeRow(left: " Kc9", fill: "9", right: "99K "),
        EdgeRow(left: "  3K", fill: "K", right: "K3  "),
    ]
    private static let ringTop: [EdgeRow] = [
        EdgeRow(left: "   3", fill: "K", right: "3   "),
        EdgeRow(left: "  KE", fill: "E", right: "DK  "),
        EdgeRow(left: " KEE", fill: "C", right: "CcK "),
        EdgeRow(left: "3EEC9", fill: " ", right: "9CCA3"),
        EdgeRow(left: "KEC9", fill: " ", right: "9C9K"),
    ]
    private static let ringMiddle = EdgeRow(left: "KEC", fill: " ", right: "C9K")
    private static let ringBottom: [EdgeRow] = [
        EdgeRow(left: "KEC9", fill: " ", right: "9C9K"),
        EdgeRow(left: "3DCC9", fill: " ", right: "9CA93"),
        EdgeRow(left: " KcC", fill: "C", right: "A9K "),
        EdgeRow(left: "  KA", fill: "9", right: "9K  "),
        EdgeRow(left: "   3", fill: "K", right: "3   "),
    ]

    static func buttonColor(_ c: RGB, _ state: ControlState) -> RGB {
        switch state {
        case .pressed:
            switch c {
            case Platinum.white: return Platinum.gray3A
            case Platinum.grayE6: return Platinum.gray73
            case Platinum.grayCE: return Platinum.gray63
            case Platinum.grayC5: return Platinum.gray94
            case Platinum.gray94: return Platinum.grayA5
            default: return c
            }
        case .disabled:
            switch c {
            case Platinum.black: return Platinum.gray94
            case Platinum.gray3A: return Platinum.grayB5
            case Platinum.gray94: return Platinum.grayC5
            default: return c
            }
        case .normal:
            return c
        }
    }

    private static func edge(_ p: PixelPainter, _ x: Int, _ y: Int, _ w: Int, _ row: EdgeRow, _ state: ControlState) {
        let left = Array(row.left), right = Array(row.right)
        for (i, ch) in left.enumerated() {
            if let c = PlatinumCode.color(ch) { p.pixel(x + i, y, buttonColor(c, state)) }
        }
        if let c = PlatinumCode.color(row.fill) {
            p.hline(x + left.count, y, w - left.count - right.count, buttonColor(c, state))
        }
        for (i, ch) in right.enumerated() {
            if let c = PlatinumCode.color(ch) { p.pixel(x + w - right.count + i, y, buttonColor(c, state)) }
        }
    }

    private static func stretch(_ p: PixelPainter, _ r: PixelRect, top: [EdgeRow], middle: EdgeRow,
                                bottom: [EdgeRow], _ state: ControlState) {
        for (i, row) in top.enumerated() { edge(p, r.x, r.y + i, r.w, row, state) }
        if r.h > top.count + bottom.count {
            for y in (r.y + top.count)..<(r.y + r.h - bottom.count) { edge(p, r.x, y, r.w, middle, state) }
        }
        for (i, row) in bottom.enumerated() { edge(p, r.x, r.y + r.h - bottom.count + i, r.w, row, state) }
    }

    /// A push button body filling r (normally 20 pixels tall).
    public static func button(_ p: PixelPainter, _ r: PixelRect, state: ControlState) {
        stretch(p, r, top: buttonTop, middle: buttonMiddle, bottom: buttonBottom, state)
    }

    /// The default button's ring, drawn around a button rect r (3 pixels outside it).
    public static func defaultRing(_ p: PixelPainter, around r: PixelRect, disabled: Bool) {
        stretch(p, r.outset(3), top: ringTop, middle: ringMiddle, bottom: ringBottom, disabled ? .disabled : .normal)
    }

    /// Label color for a button in a state.
    public static func buttonText(_ state: ControlState) -> RGB {
        switch state {
        case .normal: return Platinum.black
        case .pressed: return Platinum.white
        case .disabled: return Platinum.disabledText
        }
    }

    // MARK: - Checkboxes and radio buttons

    static let checkOff = [
        "KKKKKKKKKKKK",
        "KWWWWWWWWWEK",
        "KWEEEEEEEEAK",
        "KWEEEEEEEEAK",
        "KWEEEEEEEEAK",
        "KWEEEEEEEEAK",
        "KWEEEEEEEEAK",
        "KWEEEEEEEEAK",
        "KWEEEEEEEEAK",
        "KWEEEEEEEEAK",
        "KEAAAAAAAAAK",
        "KKKKKKKKKKKK",
    ]
    static let checkOn = [
        "KKKKKKKKKKKK  ",
        "KWWWWWWWWWEKK ",
        "KWEEEEEEEEKK9C",
        "KWEEEEEEEKKKC ",
        "KWEEEEEEKK7K  ",
        "KWKKEEEKK99K  ",
        "KWEKKEKK9CAK  ",
        "KWECKKK9CEAK  ",
        "KWEECK9CEEAK  ",
        "KWEEE9CEEEAK  ",
        "KEAAAAAAAAAK  ",
        "KKKKKKKKKKKK  ",
    ]
    static let radioOff = [
        "    6KK6    ",
        "  K7EEEc6K  ",
        " KcEFWWWEAK ",
        " 7EFWWFFEc6 ",
        "6EFWWFFEEcA6",
        "KEWWFFEEccAK",
        "KEWFFEEccCAK",
        "6cWFEEccCCA6",
        " 7EEEccCCA6 ",
        " KAcccCCAAK ",
        "  K7AAAA6K  ",
        "    6KK6    ",
    ]
    static let radioOn = [
        "    3KK3    ",
        "  3K67776K  ",
        " 367999AABK ",
        " K79KKKKBB6 ",
        "369KKKKKKBc6",
        "K79KKKKKKccK",
        "K79KKKKKKcEK",
        "37AKKKKKKEW6",
        " 3ABKKKKEW6 ",
        " 3BBBccEWWK ",
        "  36ccEW6K  ",
        "    6KK6    ",
    ]

    private static func controlColor(_ c: RGB, _ state: ControlState) -> RGB {
        switch state {
        case .pressed:
            if c == Platinum.white || c == Platinum.grayF7 { return Platinum.gray94 }
            if c == Platinum.grayE6 || c == Platinum.grayCE { return Platinum.gray73 }
            if c == Platinum.grayC5 || c == Platinum.grayA5 { return Platinum.gray63 }
            return c
        case .disabled:
            if c == Platinum.black || c == Platinum.gray3A { return Platinum.gray94 }
            if c == Platinum.gray63 || c == Platinum.gray73 { return Platinum.grayA5 }
            if c == Platinum.gray94 || c == Platinum.grayA5 { return Platinum.grayC5 }
            return c
        case .normal:
            return c
        }
    }

    /// A 12x12 checkbox at (x, y); a check mark overhangs 2 pixels to the right.
    public static func checkbox(_ p: PixelPainter, x: Int, y: Int, on: Bool, state: ControlState) {
        p.coded(on ? checkOn : checkOff, x: x, y: y) { controlColor($0, state) }
    }

    /// A mixed-state checkbox (a dash), drawn on the off box.
    public static func checkboxMixed(_ p: PixelPainter, x: Int, y: Int, state: ControlState) {
        p.coded(checkOff, x: x, y: y) { controlColor($0, state) }
        let ink = controlColor(Platinum.black, state)
        p.fill(x + 3, y + 5, 6, 2, ink)
    }

    public static func radio(_ p: PixelPainter, x: Int, y: Int, on: Bool, state: ControlState) {
        p.coded(on ? radioOn : radioOff, x: x, y: y) { controlColor($0, state) }
    }

    // MARK: - Frames

    /// Etched group box. `labelWidth` (0 for none) reserves a gap for a title
    /// whose text starts 11 pixels in; the frame runs through the title's
    /// capitals (7 pixels below the top).
    public static func groupBox(_ p: PixelPainter, _ r: PixelRect, labelWidth: Int) {
        let top = labelWidth > 0 ? r.y + 7 : r.y
        let outer = PixelRect(r.x, top, r.w - 1, r.y + r.h - top - 1)
        p.frame(PixelRect(outer.x + 1, outer.y + 1, outer.w, outer.h), Platinum.white)
        p.frame(outer, Platinum.gray94)
        if labelWidth > 0 {
            p.fill(r.x + 8, top, labelWidth + 6, 2, Platinum.face)
        }
    }

    /// An etched horizontal separator (2 rows).
    public static func separator(_ p: PixelPainter, x: Int, y: Int, w: Int) {
        p.hline(x, y, w, Platinum.gray94)
        p.hline(x + 1, y + 1, w, Platinum.white)
    }

    /// An etched vertical separator (2 columns).
    public static func verticalSeparator(_ p: PixelPainter, x: Int, y: Int, h: Int) {
        p.vline(x, y, h, Platinum.gray94)
        p.vline(x + 1, y + 1, h, Platinum.white)
    }

    /// A sunken well: gray above/left and white below/right, outside a black
    /// frame, filled inside. r is the black frame's rectangle.
    public static func sunken(_ p: PixelPainter, _ r: PixelRect, fill: RGB?) {
        p.hline(r.x - 1, r.y - 1, r.w + 1, Platinum.gray94)
        p.vline(r.x - 1, r.y - 1, r.h + 1, Platinum.gray94)
        p.hline(r.x - 1, r.y + r.h, r.w + 2, Platinum.white)
        p.vline(r.x + r.w, r.y - 1, r.h + 2, Platinum.white)
        p.frame(r, Platinum.black)
        if let fill {
            p.fill(r.inset(1), fill)
        }
    }

    /// An edit field whose black frame is r.
    public static func field(_ p: PixelPainter, _ r: PixelRect, disabled: Bool) {
        sunken(p, r, fill: disabled ? Platinum.grayF7 : Platinum.white)
        if disabled { p.frame(r, Platinum.grayA5) }
        p.hline(r.x + 1, r.y + 1, r.w - 2, Platinum.grayE6)
        p.vline(r.x + 1, r.y + 1, r.h - 2, Platinum.grayE6)
    }

    /// A list box whose black frame is r.
    public static func listBox(_ p: PixelPainter, _ r: PixelRect, disabled: Bool) {
        sunken(p, r, fill: disabled ? Platinum.grayF7 : Platinum.white)
        if disabled { p.frame(r, Platinum.grayA5) }
    }

    /// Two-pixel keyboard focus ring just outside r, with rounded outer corners.
    public static func focusRing(_ p: PixelPainter, around r: PixelRect) {
        let a = r.outset(1), b = r.outset(2)
        p.frame(a, Platinum.focusInner)
        p.hline(b.x + 1, b.y, b.w - 2, Platinum.focusOuter)
        p.hline(b.x + 1, b.y + b.h - 1, b.w - 2, Platinum.focusOuter)
        p.vline(b.x, b.y + 1, b.h - 2, Platinum.focusOuter)
        p.vline(b.x + b.w - 1, b.y + 1, b.h - 2, Platinum.focusOuter)
    }

    // MARK: - Pop-up button

    /// A small solid triangle, 7 pixels wide and 4 tall, centered on cx.
    public static func arrow(_ p: PixelPainter, cx: Int, y: Int, down: Bool, color: RGB) {
        for i in 0..<4 {
            let row = down ? i : 3 - i
            p.hline(cx - 3 + i, y + row, 7 - 2 * i, color)
        }
    }

    /// The pop-up button body; returns the text rect's x and right limit.
    @discardableResult
    public static func popup(_ p: PixelPainter, _ r: PixelRect, state: ControlState) -> (textX: Int, textMaxX: Int) {
        button(p, r, state: state)
        let ax = r.x + r.w - 19
        let dark: RGB = state == .pressed ? Platinum.gray3A : state == .disabled ? Platinum.grayC5 : Platinum.gray94
        let light: RGB = state == .pressed ? Platinum.gray63 : Platinum.white
        p.vline(ax, r.y + 3, r.h - 6, dark)
        p.vline(ax + 1, r.y + 3, r.h - 6, light)
        let ink: RGB = state == .pressed ? Platinum.white : state == .disabled ? Platinum.gray94 : Platinum.black
        arrow(p, cx: ax + 10, y: r.y + (r.h - 4) / 2, down: true, color: ink)
        return (r.x + 9, ax - 4)
    }

    // MARK: - Progress bar

    /// A progress bar whose black frame is r. `value` is 0...1, or nil for the
    /// indeterminate barber pole at animation `phase`.
    public static func progress(_ p: PixelPainter, _ r: PixelRect, value: Double?, phase: Int, disabled: Bool) {
        p.hline(r.x - 1, r.y - 1, r.w + 1, Platinum.gray94)
        p.vline(r.x - 1, r.y - 1, r.h + 1, Platinum.gray94)
        p.hline(r.x - 1, r.y + r.h, r.w + 2, Platinum.white)
        p.vline(r.x + r.w, r.y - 1, r.h + 2, Platinum.white)
        p.frame(r, Platinum.black)
        let inner = r.inset(1)
        guard !inner.isEmpty else { return }
        let n = inner.h - 1
        guard let value else {
            for y in 0..<inner.h {
                var dark = RGB(0x8C8AEF).mix(RGB(0x4A4DA5), y, n)
                var light = RGB(0xF2F1FF).mix(RGB(0xB5B2FF), y, n)
                if y == 0 { dark = RGB(0xB5B2FF); light = Platinum.white }
                // Runs of 8 pixels alternate along the row, shifted one pixel per row.
                var x = 0
                while x < inner.w {
                    let s = (((x - y + phase) % 16) + 16) % 16
                    let run = min(s < 8 ? 8 - s : 16 - s, inner.w - x)
                    let c = s < 8 ? dark : light
                    p.hline(inner.x + x, inner.y + y, run, disabled ? c.dimmed : c)
                    x += run
                }
            }
            return
        }
        let v = min(max(value, 0), 1)
        let fw = Int((v * Double(inner.w)).rounded())
        for y in 0..<inner.h {
            var bar = y == 0 ? RGB(0xC6C4FF) : RGB(0xA5A3F7).mix(RGB(0x4A4DA5), y - 1, n - 1)
            let track = y == 0 ? Platinum.grayA5 : Platinum.grayCE.mix(Platinum.grayF7, y - 1, n - 1)
            if disabled { bar = bar.dimmed }
            p.hline(inner.x, inner.y + y, fw, bar)
            p.hline(inner.x + fw, inner.y + y, inner.w - fw, track)
        }
        if fw > 0 && fw < inner.w {
            p.vline(inner.x + fw - 1, inner.y, inner.h, disabled ? Platinum.gray73 : RGB(0x3A3D8C))
        }
    }

    // MARK: - Scroll bar

    static let scrollUp = [
        "KKKKKKKKKKKKKKKK",
        "KWWWWWWWWWWWWWEK",
        "KWEEEEEEEEEEEEcK",
        "KWEEEEEEEEEEEEcK",
        "KWEEEEEEEEEEEEcK",
        "KWEEEEEEEEEEEEcK",
        "KWEEEEEKKEEEEEcK",
        "KWEEEEKKKKEEEEcK",
        "KWEEEKKKKKKEEEcK",
        "KWEEKKKKKKKKEEcK",
        "KWEEEEEEEEEEEEcK",
        "KWEEEEEEEEEEEEcK",
        "KWEEEEEEEEEEEEcK",
        "KWEEEEEEEEEEEEcK",
        "KEcccccccccccccK",
        "KKKKKKKKKKKKKKKK",
    ]
    static let thumb = [
        "KKKKKKKKKKKKKKKK",
        "KFllllllllllllaK",
        "KlaaaaaaaaaaaasK",
        "KlaaaaaaaaaaaasK",
        "KlaaFllllllaaasK",
        "KlaaadddddddaasK",
        "KlaaFllllllaaasK",
        "KlaaadddddddaasK",
        "KlaaFllllllaaasK",
        "KlaaadddddddaasK",
        "KlaaFllllllaaasK",
        "KlaaadddddddaasK",
        "KlaaaaaaaaaaaasK",
        "KlaaaaaaaaaaaasK",
        "KlaaaaaaaaaaaasK",
        "KasssssssssssssK",
        "KKKKKKKKKKKKKKKK",
    ]
    public static let thumbHeight = 17

    /// One 16x16 arrow box of a vertical scroll bar.
    public static func scrollArrow(_ p: PixelPainter, x: Int, y: Int, up: Bool, active: Bool, pressed: Bool) {
        for row in 0..<16 {
            let src = (!up && row >= 6 && row <= 9) ? 15 - row : row
            for (col, ch) in scrollUp[src].enumerated() {
                guard var c = PlatinumCode.color(ch) else { continue }
                if row >= 6 && row <= 9 && c == Platinum.black && col > 1 && col < 14 {
                    if !active { c = Platinum.grayA5 } else if pressed { c = Platinum.white }
                } else if pressed && c != Platinum.black {
                    c = c == Platinum.white ? Platinum.gray63 : Platinum.gray73
                } else if !active && c != Platinum.black {
                    c = Platinum.grayF7
                } else if !active && col > 0 && col < 15 && row == (up ? 15 : 0) {
                    c = Platinum.gray73
                }
                p.pixel(x + col, y + row, c)
            }
        }
    }

    /// A vertical scroll bar filling r (16 wide). `thumbY` is the thumb's
    /// top within r, or nil when there is nothing to scroll.
    public static func scrollBar(_ p: PixelPainter, _ r: PixelRect, thumbY: Int?, pressedArrow: Int?) {
        let active = thumbY != nil
        scrollArrow(p, x: r.x, y: r.y, up: true, active: active, pressed: pressedArrow == -1)
        scrollArrow(p, x: r.x, y: r.y + r.h - 16, up: false, active: active, pressed: pressedArrow == 1)
        let trackY = r.y + 16, trackH = r.h - 32
        guard trackH > 0 else { return }
        p.vline(r.x, trackY, trackH, Platinum.black)
        p.vline(r.x + 15, trackY, trackH, Platinum.black)
        guard let thumbY else {
            p.fill(r.x + 1, trackY, 14, trackH, Platinum.grayF7)
            return
        }
        for y in trackY..<(trackY + trackH) {
            p.pixel(r.x + 1, y, Platinum.gray94)
            p.pixel(r.x + 2, y, Platinum.grayA5)
            p.hline(r.x + 3, y, 10, Platinum.grayC5)
            p.pixel(r.x + 13, y, Platinum.grayCE)
            p.pixel(r.x + 14, y, Platinum.grayDE)
        }
        p.hline(r.x + 1, trackY, 13, Platinum.gray94)
        p.hline(r.x + 2, trackY + 1, 11, Platinum.grayA5)
        guard trackH >= thumbHeight else { return }
        let ty = min(max(thumbY, trackY), trackY + trackH - thumbHeight)
        p.coded(thumb, x: r.x, y: ty)
    }

    // MARK: - Menus

    static let checkMark = [
        ".......##",
        "......##.",
        "......##.",
        ".....##..",
        "##..##...",
        ".####....",
        "..##.....",
        "..#......",
    ]

    /// A menu's frame and face, with a soft two-pixel shadow outside r.
    public static func menu(_ p: PixelPainter, _ r: PixelRect) {
        for i in 1...2 {
            let a: CGFloat = i == 1 ? 0.5 : 0.25
            p.shade(r.x + r.w - 1 + i, r.y + i + 1, 1, r.h - 1, alpha: a)
            p.shade(r.x + i + 1, r.y + r.h - 1 + i, r.w - 2, 1, alpha: a)
        }
        p.frame(r, Platinum.black)
        p.fill(r.inset(1), Platinum.face)
        p.hline(r.x + 1, r.y + 1, r.w - 2, Platinum.white)
        p.vline(r.x + 1, r.y + 1, r.h - 2, Platinum.white)
        p.hline(r.x + 2, r.y + r.h - 2, r.w - 3, Platinum.grayB5)
        p.vline(r.x + r.w - 2, r.y + 2, r.h - 3, Platinum.grayB5)
    }

    public static func checkmark(_ p: PixelPainter, x: Int, y: Int, color: RGB) {
        for (r, row) in checkMark.enumerated() {
            for (c, ch) in row.enumerated() where ch == "#" { p.pixel(x + c, y + r, color) }
        }
    }

    // MARK: - Windows

    /// Six raised pinstripes from x0 to x1 starting at y.
    public static func pinstripes(_ p: PixelPainter, x0: Int, x1: Int, y: Int) {
        guard x1 - x0 >= 2 else { return }
        for i in 0..<6 {
            p.hline(x0 - 1, y + 2 * i, x1 - x0, Platinum.white)
            p.hline(x0, y + 2 * i + 1, x1 - x0, Platinum.gray94)
        }
    }

    /// The kinds of Platinum window frame.
    public enum WindowKind: Sendable {
        /// A document window: title bar with close, zoom and collapse boxes.
        case document
        /// A movable modal dialog: title bar, no boxes.
        case movableModal
        /// A modal dialog or alert: no title bar, thick frame.
        case modal
        /// A floating utility window with a short title bar (Mac OS 8 "floating").
        case utility
    }

    /// Content insets from the window frame (shadow excluded) for a window
    /// kind: rbui's PT_TITLE_H + 1 at the top and PT_FRAME at the sides.
    public static func contentInsets(_ kind: WindowKind) -> (top: Int, left: Int, bottom: Int, right: Int) {
        switch kind {
        case .document, .movableModal: return (21, 6, 6, 6)
        case .modal: return (6, 6, 6, 6)
        case .utility: return (14, 4, 4, 4)
        }
    }

    /// Which title-bar boxes a window shows.
    public struct TitleBoxes: Sendable, Equatable {
        public var close: Bool
        public var zoom: Bool
        public var collapse: Bool

        public init(close: Bool = false, zoom: Bool = false, collapse: Bool = false) {
            self.close = close
            self.zoom = zoom
            self.collapse = collapse
        }

        public static let none = TitleBoxes()
        public static let document = TitleBoxes(close: true, zoom: true, collapse: true)
    }

    /// Box positions within a window of width w (frame, shadow excluded).
    public static func closeBoxOrigin() -> (x: Int, y: Int) { (7, 3) }
    public static func zoomBoxOrigin(width w: Int, collapse: Bool) -> (x: Int, y: Int) {
        (w - 1 - (collapse ? 35 : 19), 3)
    }
    public static func collapseBoxOrigin(width w: Int) -> (x: Int, y: Int) { (w - 1 - 19, 3) }

    /// The window frame filling `full`, whose last row and column hold the
    /// one-pixel drop shadow. Draws the frame, the inset content well and,
    /// for titled kinds, the pinstripes around a title of `titleWidth`.
    /// Returns the title's text origin (x, baseline).
    @discardableResult
    public static func window(_ p: PixelPainter, _ full: PixelRect, kind: WindowKind, active: Bool,
                              titleWidth: Int, boxes: TitleBoxes = .none,
                              collapsed: Bool = false) -> (x: Int, baseline: Int) {
        let f = PixelRect(full.x, full.y, full.w - 1, full.h - 1)
        let x0 = f.x, y0 = f.y, x1 = f.x + f.w - 1, y1 = f.y + f.h - 1
        // Outline plus a one-pixel drop shadow on the right and bottom.
        p.frame(f, active ? Platinum.black : Platinum.gray63)
        let shadow = active ? Platinum.black : Platinum.gray94
        p.vline(x1 + 1, y0 + 1, f.h, shadow)
        p.hline(x0 + 1, y1 + 1, f.w, shadow)
        p.fill(f.inset(1), Platinum.frame)
        if active {
            // Raised outer bevel: white top/left, B5 bottom/right.
            p.hline(x0 + 1, y0 + 1, f.w - 2, Platinum.white)
            p.vline(x0 + 1, y0 + 1, f.h - 2, Platinum.white)
            p.hline(x0 + 1, y1 - 1, f.w - 2, Platinum.grayB5)
            p.vline(x1 - 1, y0 + 1, f.h - 2, Platinum.grayB5)
            p.pixel(x1 - 1, y0 + 1, Platinum.frame)
            p.pixel(x0 + 1, y1 - 1, Platinum.frame)
        }
        if !collapsed {
            let insets = contentInsets(kind)
            let c = PixelRect(x0 + insets.left, y0 + insets.top, f.w - insets.left - insets.right,
                              f.h - insets.top - insets.bottom)
            if active {
                // Inset content: B5 above/left, white below/right, then a black line.
                p.hline(c.x - 2, c.y - 2, c.w + 3, Platinum.grayB5)
                p.vline(c.x - 2, c.y - 2, c.h + 3, Platinum.grayB5)
                p.hline(c.x - 1, c.y + c.h + 1, c.w + 3, Platinum.white)
                p.vline(c.x + c.w + 1, c.y - 1, c.h + 3, Platinum.white)
            }
            p.frame(c.outset(1), active ? Platinum.black : Platinum.gray94)
            p.fill(c, Platinum.face)
        }

        guard kind != .modal else { return (0, 0) }
        let rows = kind == .utility ? 4 : 6
        let stripeTop = y0 + 3
        let tx = x0 + (f.w - titleWidth) / 2
        if active {
            var left = x0 + 9
            var right = x1 - 8
            if boxes.close { left = x0 + 7 + 13 + 4 }
            if boxes.collapse { right = x1 - 19 - 4 }
            if boxes.zoom { right = x1 - (boxes.collapse ? 35 : 19) - 4 }
            func stripes(_ a: Int, _ b: Int) {
                guard b - a >= 2 else { return }
                for i in 0..<rows {
                    p.hline(a - 1, stripeTop + 2 * i, b - a, Platinum.white)
                    p.hline(a, stripeTop + 2 * i + 1, b - a, Platinum.gray94)
                }
            }
            if titleWidth > 0 {
                stripes(left, tx - 5)
                stripes(tx + titleWidth + 5, right)
            } else {
                stripes(left, right)
            }
        }
        return (tx, kind == .utility ? y0 + 11 : y0 + 14)
    }

    /// One 13x13 title-bar box (close, zoom or collapse) with its top-left at (x, y).
    public enum TitleBox: Sendable { case close, zoom, collapse }

    public static func titleBox(_ p: PixelPainter, x: Int, y: Int, kind: TitleBox, pressed: Bool) {
        // The etched well: gray above and left, white below and right.
        p.hline(x, y, 12, Platinum.gray94)
        p.vline(x, y, 12, Platinum.gray94)
        p.hline(x + 1, y + 12, 12, Platinum.white)
        p.vline(x + 12, y + 1, 12, Platinum.white)
        // Black frame around a light, diagonally shaded face.
        let box = PixelRect(x + 1, y + 1, 11, 11)
        p.frame(box, Platinum.black)
        let ramp: [RGB] = pressed
            ? [Platinum.gray63, Platinum.gray73, Platinum.gray73, Platinum.gray94, Platinum.gray94,
               Platinum.grayA5, Platinum.grayA5, Platinum.grayB5, Platinum.grayB5, Platinum.grayC5,
               Platinum.grayC5, Platinum.grayCE, Platinum.grayCE]
            : [Platinum.gray94, Platinum.grayA5, Platinum.grayA5, Platinum.grayB5, Platinum.grayB5,
               Platinum.grayC5, Platinum.grayC5, Platinum.grayCE, Platinum.grayCE, Platinum.grayDE,
               Platinum.grayDE, Platinum.grayE6, Platinum.white]
        for yy in 0..<9 {
            for xx in 0..<9 {
                // Light at the top-left, darker toward the bottom-right.
                p.pixel(box.x + 1 + xx, box.y + 1 + yy, ramp[12 - min(12, xx + yy)])
            }
        }
        let ink = pressed ? Platinum.white : Platinum.black
        switch kind {
        case .close:
            break
        case .zoom:
            // A smaller box in the upper left of the face.
            p.frame(PixelRect(box.x + 1, box.y + 1, 6, 6), Platinum.black)
            p.hline(box.x + 1, box.y + 1, 6, ink == Platinum.white ? Platinum.white : Platinum.black)
        case .collapse:
            // Two horizontal lines across the middle (the window shade).
            p.hline(box.x + 1, box.y + 4, 9, Platinum.black)
            p.hline(box.x + 1, box.y + 6, 9, Platinum.black)
        }
    }

    /// The grow (size) box: 15x15 in the bottom-right corner of a document
    /// window's content, two overlapping squares.
    public static func growBox(_ p: PixelPainter, x: Int, y: Int, active: Bool) {
        p.fill(x, y, 15, 15, Platinum.face)
        guard active else { return }
        p.vline(x, y, 15, Platinum.black)
        p.hline(x, y, 15, Platinum.black)
        p.frame(PixelRect(x + 5, y + 5, 8, 8), Platinum.black)
        p.hline(x + 6, y + 6, 6, Platinum.white)
        p.vline(x + 6, y + 6, 6, Platinum.white)
        p.frame(PixelRect(x + 3, y + 3, 6, 6), Platinum.black)
        p.fill(x + 4, y + 4, 4, 4, Platinum.grayE6)
        p.hline(x + 4, y + 4, 4, Platinum.white)
        p.vline(x + 4, y + 4, 4, Platinum.white)
    }
}
