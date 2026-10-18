import SwiftUI

/// The Platinum bevel button (Appearance Manager's small bevel button): a
/// square-cornered, raised face for toolbars and placards, with an optional
/// 16-point icon. Original drawing in the measured Platinum palette.
public struct PlatinumBevelButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        BevelBody(configuration: configuration)
    }
}

private struct BevelBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let state: ControlState = !isEnabled ? .disabled : configuration.isPressed ? .pressed : .normal
        configuration.label
            .font(.platinumSmall)
            .foregroundStyle(state == .disabled ? Platinum.disabledText.color : Platinum.black.color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(PixelCanvas { p, r in Self.draw(p, r, state) })
            .contentShape(Rectangle())
    }

    static func draw(_ p: PixelPainter, _ r: PixelRect, _ state: ControlState) {
        let outline: RGB, light: RGB, shadow: RGB, face: RGB
        switch state {
        case .normal: (outline, light, shadow, face) = (Platinum.gray63, Platinum.white, Platinum.grayA5, Platinum.grayDE)
        case .pressed: (outline, light, shadow, face) = (Platinum.gray3A, Platinum.gray73, Platinum.grayC5, Platinum.grayA5)
        case .disabled: (outline, light, shadow, face) = (Platinum.grayB5, Platinum.grayF7, Platinum.grayCE, Platinum.grayE6)
        }
        p.frame(r, outline)
        let i = r.inset(1)
        p.fill(i, face)
        p.hline(i.x, i.y, i.w - 1, light)
        p.vline(i.x, i.y, i.h - 1, light)
        p.hline(i.x + 1, i.y + i.h - 1, i.w - 1, shadow)
        p.vline(i.x + i.w - 1, i.y + 1, i.h - 1, shadow)
    }
}

/// A bevel button with an optional icon and a small label.
public struct PlatinumBevelButton: View {
    let title: String?
    let icon: String?
    let action: () -> Void

    public init(_ title: String? = nil, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { PlatinumIcon(icon, size: 16) }
                if let title { Text(title) }
            }
        }
        .buttonStyle(PlatinumBevelButtonStyle())
        .accessibilityLabel(title ?? icon ?? "")
    }
}

/// A placard bar along a window's bottom edge: Platinum face with an etched
/// top line, for status text and bevel buttons.
public struct PlatinumPlacardBar<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        HStack(spacing: 6) { content }
            .padding(.horizontal, 6)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background {
                PixelCanvas { p, r in
                    p.fill(r, Platinum.frame)
                    p.hline(0, 0, r.w, Platinum.black)
                    p.hline(0, 1, r.w, Platinum.white)
                }
            }
    }
}
