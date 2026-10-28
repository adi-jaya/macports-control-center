#if canImport(XCTest)
import XCTest
@testable import MacPortsControlCenter
#else
import Foundation
#endif

@MainActor
final class AppStateTests: XCTestCase {
    func testCommandPaletteFilteringMatchesQuery() {
        let state = AppState(autoRefreshOnInit: false)
        let filtered = state.filteredPaletteCommands(query: "restart")
        XCTAssertFalse(filtered.isEmpty)
        XCTAssertTrue(filtered.contains(where: { $0.title.localizedCaseInsensitiveContains("Restart") }))
    }

    func testCommandPaletteFilteringEmptyReturnsAll() {
        let state = AppState(autoRefreshOnInit: false)
        let all = state.filteredPaletteCommands(query: "")
        XCTAssertFalse(all.isEmpty)
        XCTAssertTrue(all.count >= 7, "Should at least have commands for navigation and quick actions")
    }

    func testDocumentationFilesListLoadsRepositoryMarkdownFiles() {
        let state = AppState(autoRefreshOnInit: false)
        XCTAssertFalse(state.docFiles.isEmpty)
        XCTAssertTrue(state.docFiles.contains(where: { $0.fileName == "README.md" }))
    }

    func testNavigationSectionsEnumerationAndIdentification() {
        let sections = NavigationSection.allCases
        XCTAssertEqual(sections.count, 7)
        let rawValues = Set(sections.map { $0.rawValue })
        XCTAssertTrue(rawValues.contains("services"))
        XCTAssertTrue(rawValues.contains("sites"))
        XCTAssertTrue(rawValues.contains("php"))
        XCTAssertTrue(rawValues.contains("database"))
        XCTAssertTrue(rawValues.contains("packages"))
        XCTAssertTrue(rawValues.contains("logs"))
        XCTAssertTrue(rawValues.contains("docs"))

        for section in sections {
            XCTAssertEqual(section.id, section.rawValue)
            XCTAssertFalse(section.displayName.isEmpty)
            XCTAssertFalse(section.systemImage.isEmpty)
        }
    }

    func testInitialStateProperties() {
        let state = AppState(autoRefreshOnInit: false)
        XCTAssertEqual(state.selectedSection, .services)
        XCTAssertFalse(state.isCommandPalettePresented)
        XCTAssertTrue(state.isTerminalDrawerExpanded)
        XCTAssertTrue(state.services.isEmpty)
        XCTAssertTrue(state.vhosts.isEmpty)
        XCTAssertTrue(state.phpVersions.isEmpty)
        XCTAssertTrue(state.databases.isEmpty)
        XCTAssertTrue(state.packages.isEmpty)
        XCTAssertTrue(state.portSelectGroups.isEmpty)
        XCTAssertTrue(state.doctorChecks.isEmpty)
    }

    func testLoadDocContentLoadsValidMarkdown() {
        let state = AppState(autoRefreshOnInit: false)
        guard let readmeDoc = state.docFiles.first(where: { $0.fileName == "README.md" }) else {
            XCTFail("README.md should be in docFiles")
            return
        }
        let content = state.loadDocContent(doc: readmeDoc)
        XCTAssertFalse(content.isEmpty)
        XCTAssertTrue(content.contains("MacPorts") || content.contains("#"))
    }
}
