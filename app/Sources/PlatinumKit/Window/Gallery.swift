import SwiftUI

/// Every Platinum control in one window, for visual checks and screenshots.
public struct PlatinumGallery: View {
    @State private var name = "Macintosh HD"
    @State private var checked = true
    @State private var unchecked = false
    @State private var radio = 0
    @State private var popup = 1
    @State private var selection: Int? = 1

    private struct Row: Identifiable { let id: Int; let icon: String; let title: String }
    private let rows = [Row(id: 0, icon: "mac", title: "Mac"), Row(id: 1, icon: "disk", title: "Disk"),
                        Row(id: 2, icon: "cd", title: "CD"), Row(id: 3, icon: "folder", title: "Folder"),
                        Row(id: 4, icon: "network", title: "Network"), Row(id: 5, icon: "web", title: "Web"),
                        Row(id: 6, icon: "usb", title: "USB")]

    public init() {}

    public var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Emphasis: the system font").platinumText(.emphasis)
                Text("Normal: body text in the regular face, wrapping across lines as needed.")
                    .platinumText(.body)
                Text("Small: secondary text.").platinumText(.small)
                Text("Detail text is gray.").platinumText(.detail)
                Text("Large 123").platinumText(.large)
                PlatinumSeparator()
                HStack {
                    Text("Popup:").platinumText(.emphasis)
                    PlatinumPopUp(selection: $popup, options: [(0, "First choice"), (1, "Second choice"), (2, "Third")])
                }
                HStack {
                    Text("Disabled:").platinumText(.emphasis)
                    PlatinumPopUp(selection: $popup, options: [(1, "Unavailable")]).disabled(true)
                }
                PlatinumCheckbox("Checked", isOn: $checked)
                PlatinumCheckbox("Unchecked", isOn: $unchecked)
                PlatinumCheckbox("Disabled", isOn: .constant(true)).disabled(true)
                PlatinumRadioGroup(selection: $radio, options: [(0, "Selected", true), (1, "Not selected", true), (2, "Disabled option", false)])
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    PlatinumButton("Help") {}
                    Spacer()
                    PlatinumButton("Disabled") {}.disabled(true)
                    PlatinumButton("Cancel", role: .cancel) {}
                    PlatinumButton("OK", role: .default) {}
                }
            }
            .frame(width: 320)
            VStack(alignment: .leading, spacing: 10) {
                Text("Icons:").platinumText(.emphasis)
                PlatinumList(rows, selection: $selection) { row, _ in
                    HStack(spacing: 6) {
                        PlatinumIcon(row.icon, size: 16)
                        Text(row.title).platinumText(.emphasis)
                        Spacer()
                        Text("16 × 16").platinumText(.detail)
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 112)
                PlatinumGroupBox("Progress") {
                    VStack(spacing: 10) {
                        PlatinumProgressBar(value: 0.62)
                        PlatinumProgressBar(value: nil)
                        PlatinumProgressBar(value: 0.3).disabled(true)
                    }
                }
                HStack(spacing: 20) {
                    PlatinumIcon("stop", size: 32)
                    PlatinumIcon("caution", size: 32)
                    PlatinumIcon("note", size: 32)
                    PlatinumIcon("mac", size: 32)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 300)
        }
        .padding(12)
        .frame(width: 656, height: 440)
        .background(Platinum.face.color)
    }
}

/// The gallery in a full window frame, for renders.
public struct PlatinumGalleryWindow: View {
    @StateObject private var state = PlatinumWindowState(title: "Widget Gallery")
    public init() {}
    public var body: some View {
        PlatinumWindowChrome(state: state, kind: .document, boxes: .document, growable: true) {
            PlatinumGallery()
        }
        .frame(width: 656 + 13, height: 440 + 28)
        .environment(\.platinumStaticRender, true)
    }
}
