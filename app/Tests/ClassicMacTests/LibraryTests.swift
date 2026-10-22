import XCTest
@testable import ClassicMac

final class LibraryTests: XCTestCase {
    private func machine(_ id: String, family: MachineFamily = .powerMacG4, name: String? = nil) -> DownloadableMachine {
        DownloadableMachine(id: id, name: name ?? id, summary: "Summary of \(id)", osVersion: "9.2.2",
                            minimumAppVersion: "3.0.0",
                            archiveURL: URL(string: "https://example.com/\(id).tar.gz")!,
                            archiveBytes: 1_000, installedBytes: 2_000, sha256: String(repeating: "a", count: 64),
                            machineFamily: family)
    }

    func testCuratedEditionsLeadAndOlderVersionsHide() {
        let machines = [
            machine("copland-d11e4-activities-v3", family: .powerMac7500),
            machine("os922-deluxe-v5"),
            machine("os922-deluxe-v6"),
            machine("mac-os-9.2.1-ati-32gb-v4"),
            machine("os922-superdeluxe-v2"),
            machine("future-edition", name: "A Future Mac"),
        ]
        let current = LibraryEntry.entries(from: machines, includeOlder: false).map(\.id)
        XCTAssertEqual(current, ["os922-superdeluxe-v2", "os922-deluxe-v6", "mac-os-9.2.1-ati-32gb-v4",
                                 "copland-d11e4-activities-v3", "future-edition"])
        let all = LibraryEntry.entries(from: machines, includeOlder: true).map(\.id)
        XCTAssertEqual(all.last, "os922-deluxe-v5")
    }

    func testEditionMetadataAndFallbacks() {
        let deluxe = LibraryEntry(machine: machine("os922-deluxe-v6"), edition: LibraryEdition.edition(for: "os922-deluxe-v6"))
        XCTAssertEqual(deluxe.title, "Mac OS 9.2.2 Deluxe")
        XCTAssertEqual(deluxe.versionLabel, "v6")
        XCTAssertEqual(deluxe.graphicsCard, .atiRadeon)
        XCTAssertEqual(deluxe.edition?.contents.flatMap(\.items).filter { !$0.contains("After Dark") }.count ?? 0 >= 16, true)

        let unknown = LibraryEntry(machine: machine("future-edition", name: "A Future Mac"), edition: nil)
        XCTAssertEqual(unknown.title, "A Future Mac")
        XCTAssertEqual(unknown.osLabel, "Mac OS 9.2.2")
        XCTAssertEqual(unknown.graphicsCard, .standard)
        XCTAssertNil(unknown.versionLabel)

        // Copland never gets the ATI card, whatever an edition says.
        let copland = LibraryEntry(machine: machine("copland-d11e4-activities-v3", family: .powerMac7500),
                                   edition: LibraryEdition.edition(for: "copland-d11e4-activities-v3"))
        XCTAssertEqual(copland.graphicsCard, .standard)
    }

    func testSuperDeluxeListsAllFiftyFourGames() {
        let edition = LibraryEdition.edition(for: "os922-superdeluxe-v2")!
        let games = edition.contents.filter { !["Productivity", "Utilities"].contains($0.category) }
        XCTAssertEqual(games.flatMap(\.items).count, 54)
    }

    func testNewCatalogRevisionsKeepPreparedGraphicsWithoutStaleDescriptions() {
        for id in ["os922-deluxe-v9", "os922-superdeluxe-v5", "mac-os-9.2.1-ati-32gb-v5"] {
            let entry = LibraryEntry(machine: machine(id), edition: LibraryEdition.edition(for: id))
            XCTAssertNil(entry.edition)
            XCTAssertEqual(entry.description, "Summary of \(id)")
            XCTAssertEqual(entry.graphicsCard, .atiRadeon)
        }
    }
}
