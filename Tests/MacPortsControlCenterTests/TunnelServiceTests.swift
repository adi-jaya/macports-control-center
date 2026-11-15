#if canImport(XCTest)
import XCTest
@testable import MacPortsControlCenter
#else
import Foundation
#endif
import AppKit
import SwiftUI

final class TunnelServiceTests: XCTestCase {
    func testActiveTunnelModelInitializationAndCompositeID() {
        let tunnel = ActiveTunnel(port: "8081", label: "portal-berita.test", status: .starting, isVHost: true, isSSL: false)
        XCTAssertEqual(tunnel.id, "8081_portal-berita.test")
        XCTAssertEqual(tunnel.port, "8081")
        XCTAssertEqual(tunnel.status, .starting)
        XCTAssertTrue(tunnel.isVHost)
        XCTAssertFalse(tunnel.isSSL)
        XCTAssertNil(tunnel.publicUrl)
    }

    func testNavigationSectionIncludesTunnels() {
        let sections = NavigationSection.allCases
        XCTAssertTrue(sections.contains(.tunnels))
        XCTAssertEqual(NavigationSection.tunnels.displayName, "Tunnels")
        XCTAssertEqual(NavigationSection.tunnels.systemImage, "antenna.radiowaves.left.and.right")
    }
}
