import CoreGraphics

// Appearance Manager metric tables, ported from RetroBoot rbplatinum/chrome.py
// at 237fe033. Original measurements from raw Mac OS 9.2.1 framebuffers.
// Shared OS8/9 features are cross-checked against the OS8.1 archive.
// See platinum/reference/README.md for provenance and limits of coverage.
enum MeasuredChrome {
    static func color(_ ch: Character) -> RGB? {
        if ch == "." || ch == " " { return nil }
        if ch == "K" { return RGB(0) }
        if ch == "W" { return RGB(0xFFFFFF) }
        if let value = ch.hexDigitValue, ch.isNumber || ch.isLowercase {
            return RGB(UInt32(value * 17) * 0x010101)
        }
        let ramp: [Character: UInt32] = ["A":0xEEEEEE,"B":0xCCCCFF,"C":0x9999FF,
            "D":0x6666CC,"E":0x333399,"F":0x000088,"G":0x000055,"H":0]
        return ramp[ch].map(RGB.init)
    }
    static func sprite(_ p: PixelPainter, _ rows: [String], x: Int, y: Int) {
        for (j, row) in rows.enumerated() {
            for (i, ch) in row.enumerated() { if let c = color(ch) { p.pixel(x + i, y + j, c) } }
        }
    }
    static func stretch(_ p: PixelPainter, _ r: PixelRect, _ rows: [(String,String,String)], repeatAt: Int) {
        let bottom = rows.count - repeatAt - 1
        guard r.w > 0, r.h > 0 else { return }
        for y in 0..<r.h {
            let row = rows[y < repeatAt ? y : y >= r.h - bottom ? rows.count - (r.h - y) : repeatAt]
            let line = row.0 + String(repeating: row.1, count: max(0, r.w - row.0.count - row.2.count)) + row.2
            sprite(p, [String(line.prefix(r.w))], x: r.x, y: r.y + y)
        }
    }
    static let BUTTON: [(String,String,String)] = [
        ("..2K", "K", "K2.."),
        (".Kbd", "d", "dbK."),
        ("2bWW", "W", "Wdb2"),
        ("KdWW", "d", "da7K"),
        ("KdWd", "d", "da7K"),
        ("KdWd", "d", "aa7K"),
        ("2bda", "a", "a772"),
        (".Kb7", "7", "77K."),
        ("..2K", "K", "K2.."),
    ]
    static let BUTTON_PRESSED: [(String,String,String)] = [
        ("..2K", "K", "K2.."),
        (".K44", "4", "44K."),
        ("2445", "5", "5672"),
        ("K455", "6", "678K"),
        ("K456", "6", "678K"),
        ("K456", "6", "778K"),
        ("2467", "7", "7882"),
        (".K78", "8", "88K."),
        ("..2K", "K", "K2.."),
    ]
    static let BUTTON_DISABLED: [(String,String,String)] = [
        ("..88", "8", "88.."),
        (".8dd", "d", "dd8."),
        ("8ddd", "d", "ddd8"),
        (".8dd", "d", "dd8."),
        ("..88", "8", "88.."),
    ]
    static let BUTTON_DEFAULT: [(String,String,String)] = [
        ("...2KKKK", "K", "KKKK2..."),
        ("..Kddddd", "d", "ddddcK.."),
        (".Kddaaaa", "a", "aaaaabK."),
        ("2dda72KK", "K", "KK27aa82"),
        ("Kda7Kbdd", "d", "ddbK7a7K"),
        ("Kda2bWWW", "W", "WWdb2a7K"),
        ("KdaKdWWd", "d", "dda7Ka7K"),
        ("KdaKdWdd", "d", "dda7Ka7K"),
        ("KdaKdWdd", "d", "daa7Ka7K"),
        ("Kda2bdaa", "a", "aa772a7K"),
        ("Kda7Kb77", "7", "777K7a7K"),
        ("2caa72KK", "K", "KK27a872"),
        (".Kbaaaaa", "a", "aaaa87K."),
        ("..K87777", "7", "77777K.."),
        ("...2KKKK", "K", "KKKK2..."),
    ]
    static let BUTTON_DEFAULT_PRESSED: [(String,String,String)] = [
        ("...2KKKK", "K", "KKKK2..."),
        ("..Kddddd", "d", "ddddcK.."),
        (".Kddaaaa", "a", "aaaaabK."),
        ("2dda72KK", "K", "KK27aa82"),
        ("Kda7K444", "4", "444K7a7K"),
        ("Kda24455", "5", "55672a7K"),
        ("KdaK4556", "6", "6678Ka7K"),
        ("KdaK4566", "6", "6678Ka7K"),
        ("KdaK4566", "6", "6778Ka7K"),
        ("Kda24677", "7", "77882a7K"),
        ("Kda7K788", "8", "888K7a7K"),
        ("2caa72KK", "K", "KK27a872"),
        (".Kbaaaaa", "a", "aaaa87K."),
        ("..K87777", "7", "77777K.."),
        ("...2KKKK", "K", "KKKK2..."),
    ]
    static let FIELD: [(String,String,String)] = [
        ("88", "8", "8."),
        ("8K", "K", "KW"),
        ("8K", " ", "KW"),
        ("8K", "K", "KW"),
        (".W", "W", "WW"),
    ]
    static let FIELD_FOCUS: [(String,String,String)] = [
        (".DD", "D", "DD."),
        ("DDD", "D", "DDD"),
        ("DDK", "K", "KDD"),
        ("DDK", " ", "KDD"),
        ("DDK", "K", "KDD"),
        ("DDD", "D", "DDD"),
        (".DD", "D", "DD."),
    ]
    static let GROUP: [(String,String,String)] = [
        ("88", "8", "8."),
        ("8W", "W", "8W"),
        ("8W", " ", "8W"),
        ("88", "8", "8W"),
        (".W", "W", "WW"),
    ]
    static let CHECKBOX: [String:[String]] = [
        "off": ["KKKKKKKKKKKK..", "KWWWWWWWWWdK..", "KWdddddddd8K..", "KWdddddddd8K..", "KWdddddddd8K..", "KWdddddddd8K..", "KWdddddddd8K..", "KWdddddddd8K..", "KWdddddddd8K..", "KWdddddddd8K..", "Kd888888888K..", "KKKKKKKKKKKK.."],
        "on": ["KKKKKKKKKKKK..", "KWWWWWWWWWdKK.", "KWddddddddKK7a", "KWdddddddKKKa.", "KWddddddKK5K..", "KWKKdddKK77K..", "KWdKKdKK7a8K..", "KWdaKKK7ad8K..", "KWddaK7add8K..", "KWddd7addd8K..", "Kd888888888K..", "KKKKKKKKKKKK.."],
        "off-pressed": ["KKKKKKKKKKKK..", "K5555555557K..", "K5777777779K..", "K5777777779K..", "K5777777779K..", "K5777777779K..", "K5777777779K..", "K5777777779K..", "K5777777779K..", "K5777777779K..", "K7999999999K..", "KKKKKKKKKKKK.."],
        "on-pressed": ["KKKKKKKKKKKK..", "K5555555557KK.", "K577777777KK57", "K57777777KKK7.", "K5777777KK4K..", "K5KK777KK45K..", "K57KK7KK459K..", "K575KKK4579K..", "K5775K45779K..", "K5777457779K..", "K7999999999K..", "KKKKKKKKKKKK.."],
        "on-disabled": ["888888888888..", "8dddddddddd88.", "8ddddddddd88..", "8dddddddd888..", "8ddddddd88d8..", "8d88ddd88dd8..", "8dd88d88ddd8..", "8ddd888dddd8..", "8dddd8ddddd8..", "8dddddddddd8..", "8dddddddddd8..", "888888888888.."],
        "off-disabled": ["888888888888..", "8dddddddddd8..", "8dddddddddd8..", "8dddddddddd8..", "8dddddddddd8..", "8dddddddddd8..", "8dddddddddd8..", "8dddddddddd8..", "8dddddddddd8..", "8dddddddddd8..", "8dddddddddd8..", "888888888888.."],
    ]
    static let RADIO: [String:[String]] = [
        "off": ["....4KK4....", "..K5dddb4K..", ".KbdeWWWd8K.", ".5deWWeedb4.", "4deWWeeddb84", "KdWWeeddbb8K", "KdWeeddbba8K", "4bWeddbbaa84", ".5dddbbaa84.", ".K8bbbaa88K.", "..K588884K..", "....4KK4...."],
        "on": ["....2KK2....", "..2K45554K..", ".245777889K.", ".K57KKKK994.", "247KKKKKK9b4", "K57KKKKKKbbK", "K57KKKKKKbdK", "258KKKKKKdW4", ".289KKKKdW4.", ".2999bbdWWK.", "..24bbdW4K..", "....4KK4...."],
        "off-pressed": ["....2KK2....", "..2K44444K..", ".244556667K.", ".K455667774.", "245566777894", "K4566777889K", "K4667778899K", "2467778899b4", ".26778899b5.", ".4778899bbK.", "..24999b5K..", "....4KK4...."],
        "on-pressed": ["....2KK2....", "..2K44444K..", ".244556667K.", ".K45KKKK774.", "245KKKKKK894", "K45KKKKKK89K", "K46KKKKKK99K", "246KKKKKK9b4", ".267KKKK9b5.", ".4778899bbK.", "..24999b5K..", "....4KK4...."],
        "off-disabled": ["....8888....", "..8ddddd88..", ".8dddddddd8.", ".ddddddddd8.", "8dddddddddd8", "8dddddddddd8", "8dddddddddd8", "8dddddddddd8", ".ddddddddd8.", ".8dddddddd8.", "..8ddddd88..", "....8888...."],
        "on-disabled": ["....8888....", "..8ddddd88..", ".8dddddddd8.", ".ddd8888dd8.", "8dd888888dd8", "8dd888888dd8", "8dd888888dd8", "8dd888888dd8", ".ddd8888dd8.", ".8dddddddd8.", "..8ddddd88..", "....8888...."],
    ]
    static let POPUP_LEFT = ["..2K", ".KWW", "2Wdd", "KWdd", "KWdd", "KWdd", "KWdd", "KWdd", "KWdd", "KWdd", "KWdd", "KWdd", "KWdd", "KWdd", "KWdd", "KWdd", "KWdd", "2Wdd", ".Kaa", "..2K"]
    static let POPUP_FILL = ["K", "W", "d", "d", "d", "d", "d", "d", "d", "d", "d", "d", "d", "d", "d", "d", "d", "d", "a", "K"]
    static let POPUP_RIGHT = ["KKKKKKKKKKKKKKKKKKK2..", "dddddddddddddddddddbK.", "adWWWWWWWWWWWWWWWWWda2", "adWdddddddddddddddda7K", "adWdddddddddddddddda7K", "adWdddddddKdddddddda7K", "adWddddddKKKddddddda7K", "adWdddddKKKKKdddddda7K", "adWddddKKKKKKKddddda7K", "adWdddddddddddddddda7K", "adWdddddddddddddddda7K", "adWddddKKKKKKKddddda7K", "adWdddddKKKKKdddddda7K", "adWddddddKKKddddddda7K", "adWdddddddKdddddddda7K", "adWdddddddddddddddda7K", "adWdddddddddddddddda7K", "addaaaaaaaaaaaaaaaa772", "ab777777777777777777K.", "KKKKKKKKKKKKKKKKKKK2.."]
    static let POPUP_DIS_LEFT = ["..88", ".8dd", "8ddd", "8ddd", "8ddd", "8ddd", "8ddd", "8ddd", "8ddd", "8ddd", "8ddd", "8ddd", "8ddd", "8ddd", "8ddd", "8ddd", "8ddd", "8ddd", ".8dd", "..88"]
    static let POPUP_DIS_FILL = ["8", "d", "d", "d", "d", "d", "d", "d", "d", "d", "d", "d", "d", "d", "d", "d", "d", "d", "d", "8"]
    static let POPUP_DIS_RIGHT = ["88888888888888888888..", "addddddddddddddddddd8.", "adddddddddddddddddddd8", "adddddddddddddddddddd8", "adddddddddddddddddddd8", "addddddddd8dddddddddd8", "adddddddd888ddddddddd8", "addddddd88888dddddddd8", "adddddd8888888ddddddd8", "adddddddddddddddddddd8", "adddddddddddddddddddd8", "adddddd8888888ddddddd8", "addddddd88888dddddddd8", "adddddddd888ddddddddd8", "addddddddd8dddddddddd8", "adddddddddddddddddddd8", "adddddddddddddddddddd8", "adddddddddddddddddddd8", "addddddddddddddddddd8.", "88888888888888888888.."]
    static let POPUP_PRESSED: [(String,String,String)] = [
        ("dd2K", "K", "KKKKKKKKKKKKKKKKKKK2dd"),
        ("dK55", "5", "64444444444444444444Kd"),
        ("2556", "6", "7455555555555555555682"),
        ("K566", "6", "745666666666666666678K"),
        ("K566", "6", "745666666666666666678K"),
        ("K566", "6", "7456666666W6666666678K"),
        ("K566", "6", "745666666WWW666666678K"),
        ("K566", "6", "74566666WWWWW66666678K"),
        ("K566", "6", "7456666WWWWWWW6666678K"),
        ("K566", "6", "745666666666666666678K"),
        ("K566", "6", "745666666666666666678K"),
        ("K566", "6", "7456666WWWWWWW6666678K"),
        ("K566", "6", "74566666WWWWW66666678K"),
        ("K566", "6", "745666666WWW666666678K"),
        ("K566", "6", "7456666666W6666666678K"),
        ("K566", "6", "745666666666666666678K"),
        ("K566", "6", "745666666666666666678K"),
        ("2566", "6", "7467777777777777777882"),
        ("dK77", "7", "74888888888888888888Kd"),
        ("dd2K", "K", "KKKKKKKKKKKKKKKKKKK2dd"),
    ]
    static let DEFAULT_DISABLED: [(String,String,String)] = [
        ("ddd88888", "8", "88888ddd"),
        ("dd8bbbbb", "b", "bbbbb8dd"),
        ("d8bbbbbb", "b", "bbbbbb8d"),
        ("8bbbb888", "8", "888bbbb8"),
        ("8bbb8ddd", "d", "ddd8bbb8"),
        ("8bb8dddd", "d", "dddd8bb8"),
        ("8bb8dddd", "d", "dddd8bb8"),
        ("8bb8dddd", "d", "dddd8bb8"),
        ("8bb8dddd", "d", "dddd8bb8"),
        ("8bb8dddd", "d", "dddd8bb8"),
        ("8bb8dddd", "d", "dddd8bb8"),
        ("8bb8dddd", "d", "dddd8bb8"),
        ("8bb8dddd", "d", "dddd8bb8"),
        ("8bb8dddd", "d", "dddd8bb8"),
        ("8bb8dddd", "d", "dddd8bb8"),
        ("8bb8dddd", "d", "dddd8bb8"),
        ("8bb8dddd", "d", "dddd8bb8"),
        ("8bb8dddd", "d", "dddd8bb8"),
        ("8bb8dddd", "d", "dddd8bb8"),
        ("8bb8dddd", "d", "dddd8bb8"),
        ("8bb8dddd", "d", "dddd8bb8"),
        ("8bbb8ddd", "d", "ddd8bbb8"),
        ("8bbbb888", "8", "888bbbb8"),
        ("d8bbbbbb", "b", "bbbbbb8d"),
        ("dd8bbbbb", "b", "bbbbb8dd"),
        ("ddd88888", "8", "88888ddd"),
    ]
    static let RADIO_OFF_DISABLED = ["dddd8888dddd", "dd88dddd88dd", "d8dddddddd8d", "d8dddddddd8d", "8dddddddddd8", "8dddddddddd8", "8dddddddddd8", "8dddddddddd8", "d8dddddddd8d", "d8dddddddd8d", "dd88dddd88dd", "dddd8888dddd"]
    static let RADIO_ON_DISABLED = ["dddd8888dddd", "dd88dddd88dd", "d8dddddddd8d", "d8dd8888dd8d", "8dd888888dd8", "8dd888888dd8", "8dd888888dd8", "8dd888888dd8", "d8dd8888dd8d", "d8dddddddd8d", "dd88dddd88dd", "dddd8888dddd"]
    static let CHECKBOX_MIXED = ["KKKKKKKKKKKKdd", "KWWWWWWWWWdKdd", "KWdddddddd8Kdd", "KWdddddddd8Kdd", "KWdddddddd8Kdd", "KWdKKKKKKa8Kdd", "KWdKKKKKKa8Kdd", "KWddaaaaaa8Kdd", "KWdddddddd8Kdd", "KWdddddddd8Kdd", "Kd888888888Kdd", "KKKKKKKKKKKKdd"]
    static let CHECKBOX_MIXED_PRESSED = ["KKKKKKKKKKKKdd", "K5555555557Kdd", "K5777777779Kdd", "K5777777779Kdd", "K5777777779Kdd", "K57KKKKKK59Kdd", "K57KKKKKK59Kdd", "K5775555559Kdd", "K5777777779Kdd", "K5777777779Kdd", "K7999999999Kdd", "KKKKKKKKKKKKdd"]
    static let CHECKBOX_MIXED_DISABLED = ["888888888888dd", "8dddddddddd8dd", "8dddddddddd8dd", "8dddddddddd8dd", "8dddddddddd8dd", "8dd888888dd8dd", "8dd888888dd8dd", "8dddddddddd8dd", "8dddddddddd8dd", "8dddddddddd8dd", "8dddddddddd8dd", "888888888888dd"]
}
