import AppKit
import SwiftUI
import PlatinumKit

/// The Mac OS Library: ready-to-run Macs to download, from the ClassicMac
/// catalog, described with what is inside each one.
struct LibraryView: View {
    @StateObject private var model = MachineDownloadModel()
    @State private var selection: String?
    @State private var showOlder = false
    @State private var name = ""
    @State private var saveFolder = AppPaths.defaultLibraryDir
    @State private var supportsSparse = false
    @State private var progress: PlatinumWindow?

    private var entries: [LibraryEntry] {
        LibraryEntry.entries(from: model.machines, includeOlder: showOlder)
    }

    private var selected: LibraryEntry? {
        entries.first { $0.id == selection } ?? entries.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                PlatinumIcon("library", size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose a Mac to download.").platinumText(.emphasis)
                    Text("Each one is a complete Mac, ready to start: download it once to create your own independent copy.")
                        .platinumText(.small)
                }
                Spacer()
            }
            if model.machines.isEmpty {
                catalogState
            } else {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        PlatinumList(entries, selection: $selection, rowHeight: 40) { entry, _ in
                            LibraryRow(entry: entry, partial: model.hasPartialDownload(entry.machine))
                        }
                        PlatinumCheckbox("Show older versions", isOn: $showOlder)
                    }
                    .frame(width: 300)
                    if let entry = selected {
                        LibraryDetail(entry: entry, supportsSparse: supportsSparse)
                            .id(entry.id)
                    }
                }
                PlatinumSeparator()
                downloadRow
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Platinum.face.color)
        .task { model.loadCatalog() }
        .task(id: saveFolder) {
            let folder = saveFolder
            supportsSparse = await Task.detached(priority: .utility) {
                MachineTemplateInstaller.supportsSparseFiles(at: folder)
            }.value
        }
        .onChange(of: selected?.id, initial: true) { _, _ in
            if let selected { name = selected.title }
        }
        .onChange(of: model.phase) { _, phase in phaseChanged(phase) }
        .onChange(of: model.errorMessage) { _, message in
            guard let message, model.machines.isEmpty == false else { return }
            closeProgress()
            WindowManager.shared.alert(.stop, "The Mac could not be downloaded.", informative: message,
                                       buttons: [PlatinumAlertButton("OK", role: .default)],
                                       parent: WindowManager.shared.libraryWindowRef)
        }
    }

    // MARK: Catalog loading and errors

    @ViewBuilder
    private var catalogState: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.phase == .loadingCatalog {
                Text("Looking for Macs in the Library…").platinumText(.body)
                PlatinumProgressBar(value: nil).frame(width: 320)
            } else if let error = model.errorMessage {
                HStack(alignment: .top, spacing: 12) {
                    PlatinumIcon("stop", size: 32)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("The Library could not be opened.").platinumText(.emphasis)
                        Text(error).platinumText(.small).fixedSize(horizontal: false, vertical: true)
                        PlatinumButton("Try Again", role: .default) { model.loadCatalog() }
                    }
                }
            } else {
                Text("No Macs are in the Library right now. Check again soon, or create a Mac from your own Mac OS CD.")
                    .platinumText(.body)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 20)
    }

    // MARK: Download

    private var downloadRow: some View {
        let entry = selected
        let partial = entry.map { model.hasPartialDownload($0.machine) } ?? false
        let compatible = entry.map { (try? $0.machine.checkCompatibility()) != nil } ?? false
        let validName = (try? MachineTemplateInstaller.normalizedName(name)) != nil
        return HStack(spacing: 10) {
            Text("Name:").platinumText(.emphasis)
            PlatinumTextField(text: $name, width: 200)
            Text("Save in:").platinumText(.emphasis)
            PlatinumIcon("folder", size: 16)
            Text(saveFolder.lastPathComponent).platinumText(.body).lineLimit(1).help(saveFolder.path)
                .frame(maxWidth: 110, alignment: .leading)
            PlatinumButton("Choose…", action: chooseFolder)
            Spacer(minLength: 0)
            if partial, let entry {
                PlatinumButton("Discard") { model.discardDownload(entry.machine) }
            }
            PlatinumButton(partial ? "Resume" : "Download", role: .default, minWidth: 90) {
                if let entry { download(entry) }
            }
            .disabled(entry == nil || model.isBusy || !validName || !compatible)
        }
        .disabled(model.isBusy)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = saveFolder
        panel.prompt = "Choose"
        panel.message = "Choose where to save the downloaded Mac"
        if panel.runModal() == .OK, let url = panel.url { saveFolder = url }
    }

    private func download(_ entry: LibraryEntry) {
        let title = entry.title
        let card = entry.graphicsCard
        progress = WindowManager.shared.presentDialog(title: "Downloading", size: DownloadProgressView.size,
                                                      parent: WindowManager.shared.libraryWindowRef) { _ in
            DownloadProgressView(model: model, title: title)
        }
        model.install(entry.machine, name: name, directory: saveFolder) { url in
            installed(url, title: title, card: card)
        }
    }

    private func installed(_ url: URL, title: String, card: GraphicsCard) {
        let store = VMStore.shared
        store.openBundle(at: url, autostart: false)
        guard let id = store.selectedID, var vm = store.vms.first(where: { $0.id == id }) else { return }
        if vm.graphicsCard != card {
            vm.graphicsCard = card
            if card == .atiRadeon {
                let size = ATIDisplay.size(fitting: vm.width, height: vm.height)
                vm.width = size.width
                vm.height = size.height
            }
            _ = store.save(vm)
        }
        closeProgress()
        WindowManager.shared.alert(.note, "\u{201C}\(vm.name)\u{201D} is ready.",
            informative: "It is in the list of Macs on this computer. Start it up whenever you like." +
                (card == .atiRadeon ? " It uses the ATI Radeon card, so 3D games are accelerated." : ""),
            buttons: [
                PlatinumAlertButton("Start Up", role: .default) {
                    WindowManager.shared.showMain()
                    QEMUManager.shared.start(vm)
                },
                PlatinumAlertButton("Later", role: .cancel) { WindowManager.shared.showMain() },
            ], parent: WindowManager.shared.libraryWindowRef)
    }

    private func phaseChanged(_ phase: MachineDownloadModel.Phase) {
        switch phase {
        case .paused, .idle:
            closeProgress()
        default:
            break
        }
    }

    private func closeProgress() {
        progress?.close()
        progress = nil
    }
}

/// A catalog entry in the Library list.
private struct LibraryRow: View {
    let entry: LibraryEntry
    let partial: Bool

    var body: some View {
        HStack(spacing: 8) {
            PlatinumIcon(entry.machine.family.iconName, size: 32)
                .overlay(alignment: .bottomTrailing) {
                    PlatinumIcon("web", size: 16).offset(x: 4, y: 3)
                }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(entry.title).platinumText(.emphasis).lineLimit(1)
                    if let version = entry.versionLabel {
                        Text(version).platinumText(.detail)
                    }
                }
                Text(partial ? "Download paused" : entry.tagline).platinumText(.detail).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(ByteCountFormatter.string(fromByteCount: entry.machine.archiveBytes, countStyle: .file))
                .platinumText(.detail)
        }
        .padding(.horizontal, 5)
        .accessibilityElement(children: .combine)
    }
}

/// Everything about one Library Mac.
private struct LibraryDetail: View {
    let entry: LibraryEntry
    let supportsSparse: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                PlatinumIcon(entry.machine.family.iconName, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title + (entry.versionLabel.map { " \($0)" } ?? "")).platinumText(.emphasis)
                    Text("\(entry.osLabel) · \(entry.machine.family.label) · \(entry.graphicsCard.label) graphics")
                        .platinumText(.detail)
                }
            }
            Text(entry.description).platinumText(.body).fixedSize(horizontal: false, vertical: true)
            PlatinumWell {
                PlatinumScrollView(line: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let edition = entry.edition {
                            ForEach(Array(edition.contents.enumerated()), id: \.offset) { _, group in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(group.category) (\(group.items.count))").platinumText(.emphasis)
                                    Text(group.items.joined(separator: ", ")).platinumText(.small)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            if !edition.notes.isEmpty {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Good to know").platinumText(.emphasis)
                                    ForEach(edition.notes, id: \.self) { note in
                                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                                            Text("•").platinumText(.small)
                                            Text(note).platinumText(.small).fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        } else {
                            Text(entry.machine.summary).platinumText(.small)
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: .infinity)
            sizes
            if (try? entry.machine.checkCompatibility()) == nil {
                HStack(spacing: 6) {
                    PlatinumIcon("caution", size: 16)
                    Text("Needs ClassicMac \(entry.machine.minimumAppVersion) or later.").platinumText(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sizes: some View {
        let storage = MachineTemplateStoragePlan(machine: entry.machine, supportsSparseFiles: supportsSparse)
        let download = ByteCountFormatter.string(fromByteCount: entry.machine.archiveBytes, countStyle: .file)
        let needed = ByteCountFormatter.string(fromByteCount: storage.requiredBytes + MachineTemplateInstaller.spaceReserve,
                                               countStyle: .file)
        var line = "\(download) download · needs \(needed) free"
        if let capacity = entry.machine.diskCapacityBytes {
            line += " · \(ByteCountFormatter.string(fromByteCount: capacity, countStyle: .memory)) disk"
        }
        return Text(line).platinumText(.detail)
    }
}

/// The classic copy-progress dialog for a Library download.
struct DownloadProgressView: View {
    static let size = NSSize(width: 420, height: 112)

    @ObservedObject var model: MachineDownloadModel
    let title: String
    @State private var started = Date()
    @State private var startBytes: Int64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                PlatinumIcon("library", size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(heading).platinumText(.emphasis).lineLimit(1)
                    Text(detail).platinumText(.small).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            PlatinumProgressBar(value: fraction)
            HStack {
                Spacer()
                PlatinumButton(model.phase == .downloading ? "Stop" : "Cancel", role: .cancel) { model.cancel() }
                    .disabled(model.isCancelling || !model.isBusy)
            }
        }
        .padding(12)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Platinum.face.color)
        .onChange(of: model.phase) { _, _ in
            started = Date()
            startBytes = model.completedBytes
        }
    }

    private var heading: String {
        switch model.phase {
        case .downloading: return "Downloading \u{201C}\(title)\u{201D}…"
        case .verifying: return "Checking \u{201C}\(title)\u{201D}…"
        case .installing: return "Preparing \u{201C}\(title)\u{201D}…"
        default: return model.activityLabel
        }
    }

    private var fraction: Double? {
        guard model.totalBytes > 0 else { return nil }
        return Double(model.completedBytes) / Double(model.totalBytes)
    }

    private var detail: String {
        if model.isCancelling { return "Stopping. Your download is saved." }
        let done = ByteCountFormatter.string(fromByteCount: model.completedBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: model.totalBytes, countStyle: .file)
        var text = "\(done) of \(total)"
        let elapsed = Date().timeIntervalSince(started)
        let moved = Double(model.completedBytes - startBytes)
        if model.phase == .downloading, elapsed > 3, moved > 0 {
            let remaining = Double(model.totalBytes - model.completedBytes) / (moved / elapsed)
            text += " · " + Self.remaining(remaining)
        }
        return text
    }

    static func remaining(_ seconds: Double) -> String {
        if seconds < 60 { return "Less than a minute remaining" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "About \(minutes) minute\(minutes == 1 ? "" : "s") remaining" }
        let hours = Int((seconds / 3600).rounded())
        return "About \(hours) hour\(hours == 1 ? "" : "s") remaining"
    }
}
