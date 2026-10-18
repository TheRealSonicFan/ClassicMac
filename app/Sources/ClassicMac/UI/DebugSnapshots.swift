import AppKit
import PlatinumKit

/// Development aid: with CLASSICMAC_UI_SNAPSHOTS=<folder> set, ClassicMac opens
/// the windows named in CLASSICMAC_UI_TOUR (comma separated: library, about,
/// settings, newmac, media, alert, shutdown), renders every visible window to
/// a PNG in that folder at the screen's scale, and quits. Run it with
/// CFFIXED_USER_HOME pointing at a scratch home so no real Macs are touched.
@MainActor
enum DebugSnapshots {
    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let folder = env["CLASSICMAC_UI_SNAPSHOTS"] else { return }
        let tour = (env["CLASSICMAC_UI_TOUR"] ?? "").split(separator: ",").map(String.init)
        let out = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            for step in tour {
                open(step)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            var index = 0
            for window in NSApp.orderedWindows.reversed() where window.isVisible {
                index += 1
                let name = String(format: "%02d-%@.png", index,
                                  window.title.isEmpty ? "window" : window.title.replacingOccurrences(of: "/", with: "-"))
                write(window, to: out.appendingPathComponent(name))
            }
            if env["CLASSICMAC_UI_STAY"] == nil { NSApp.terminate(nil) }
        }
    }

    private static func open(_ step: String) {
        let manager = WindowManager.shared
        let store = VMStore.shared
        switch step {
        case "library": manager.showLibrary()
        case "about": manager.showAbout()
        case "newmac": manager.presentNewMac()
        case "settings": if let id = store.selectedID { manager.presentSettings(for: id) }
        case "media": if let id = store.selectedID { MediaController.shared.present(for: id) }
        case "shutdown": if let id = store.selectedID { QEMUManager.shared.requestStop(id) }
        case "alert":
            manager.alert(.caution, "This is a Platinum alert.", informative: "Buttons, icon and text follow the Mac OS alert layout.",
                          buttons: [PlatinumAlertButton("OK", role: .default), PlatinumAlertButton("Cancel", role: .cancel)])
        case "collapse": (NSApp.orderedWindows.first { $0.isVisible } as? PlatinumWindow)?.toggleCollapse()
        default:
            if step.hasPrefix("select:"), let n = Int(step.dropFirst(7)), store.vms.indices.contains(n) {
                store.selectedID = store.vms[n].id
            }
        }
    }

    private static func write(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView else { return }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
