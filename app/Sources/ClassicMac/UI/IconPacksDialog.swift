import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PlatinumKit

/// Lets the person add The Iconfactory's classic Mac icons they downloaded.
struct IconPacksDialog: View {
    static let size = NSSize(width: 500, height: 330)

    let handle: DialogHandle
    @ObservedObject private var packs = IconPacks.shared
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Classic Mac icons from The Iconfactory").platinumText(.emphasis)
            Text("The Iconfactory's classic Macintosh icons suit ClassicMac perfectly. They are free for personal use and may not be redistributed, so ClassicMac doesn\u{2019}t include them. Download the collections you like, such as Apple Desktops and Expo, then add the downloaded disk images here. ClassicMac keeps a copy on this computer, with its license.")
                .platinumText(.small)
                .fixedSize(horizontal: false, vertical: true)
            PlatinumGroupBox(packs.isUsingIconfactory ? "Now showing" : "Now showing ClassicMac\u{2019}s own icons") {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(IconPacks.choices, id: \.icon) { choice in
                        VStack(spacing: 4) {
                            PlatinumIcon(choice.icon, size: 32)
                            Text(choice.label).platinumText(.small)
                            Text(packs.activeIcons[choice.icon] ?? "ClassicMac")
                                .platinumText(.detail).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            if packs.isImporting {
                HStack(spacing: 8) {
                    Text("Adding icons…").platinumText(.small)
                    PlatinumProgressBar(value: nil).frame(width: 160)
                }
            } else if let errorMessage {
                HStack(alignment: .top, spacing: 6) {
                    PlatinumIcon("caution", size: 16)
                    Text(errorMessage).platinumText(.small).fixedSize(horizontal: false, vertical: true)
                }
            } else if !packs.collections.isEmpty {
                Text("Collections on this computer: " + packs.collections.joined(separator: ", ") + ".")
                    .platinumText(.detail).lineLimit(2)
            }
            Spacer(minLength: 0)
            HStack(spacing: Platinum.buttonGap) {
                PlatinumButton("Visit The Iconfactory") { NSWorkspace.shared.open(IconPacks.website) }
                if !packs.collections.isEmpty {
                    PlatinumButton("Remove Icons") { packs.removeAll() }
                }
                Spacer()
                PlatinumButton("Add Icons…", action: chooseCollections)
                    .disabled(packs.isImporting)
                PlatinumButton("Done", role: .default) { handle.close() }
            }
        }
        .padding(12)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Platinum.face.color)
    }

    private func chooseCollections() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.diskImage, .folder]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.message = "Choose the Iconfactory disk images (or folders) you downloaded"
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        errorMessage = nil
        Task {
            do { try await packs.add(urls) } catch { errorMessage = error.localizedDescription }
        }
    }
}
