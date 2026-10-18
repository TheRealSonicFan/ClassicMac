import SwiftUI

/// The icon of a Platinum alert.
public enum PlatinumAlertIcon: String, Sendable {
    case note, caution, stop

    var iconName: String { rawValue }
}

/// One button of an alert, right to left in `buttons` order: the first is
/// the default (rightmost).
public struct PlatinumAlertButton: Identifiable {
    public let id = UUID()
    public let title: String
    public let role: PlatinumButton<Text>.Role
    public let action: () -> Void

    public init(_ title: String, role: PlatinumButton<Text>.Role = .normal, action: @escaping () -> Void = {}) {
        self.title = title
        self.role = role
        self.action = action
    }
}

/// The content of a Platinum alert, laid out as Mac OS alerts were: the
/// 32-point icon in the upper left, the message in the system font, an
/// optional explanation in the small font, and the buttons at the bottom
/// right with the default button rightmost.
public struct PlatinumAlert: View {
    let icon: PlatinumAlertIcon
    let message: String
    let informative: String?
    let buttons: [PlatinumAlertButton]
    let width: CGFloat
    let dismiss: () -> Void
    let extra: AnyView?

    public init(icon: PlatinumAlertIcon, message: String, informative: String? = nil,
                buttons: [PlatinumAlertButton], width: CGFloat = 400,
                extra: AnyView? = nil, dismiss: @escaping () -> Void) {
        self.icon = icon
        self.message = message
        self.informative = informative
        self.buttons = buttons
        self.width = width
        self.extra = extra
        self.dismiss = dismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                PlatinumIcon(icon.iconName, size: 32)
                    .padding(.leading, 20)
                    .padding(.top, 10)
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .platinumText(.emphasis)
                        .fixedSize(horizontal: false, vertical: true)
                    if let informative {
                        Text(informative)
                            .platinumText(.small)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let extra { extra }
                }
                .padding(.leading, 23)
                .padding(.top, 11)
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: Platinum.buttonGap) {
                Spacer(minLength: 0)
                ForEach(buttons.reversed()) { button in
                    PlatinumButton(button.title, role: button.role) {
                        dismiss()
                        button.action()
                    }
                }
            }
            .padding(.top, 16)
            .padding(.trailing, 10)
            .padding(.bottom, 10)
        }
        .frame(width: width)
    }
}
