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

    func testExtractTunnelURLFromRealisticCloudflareLog() {
        let sampleLog = """
        2026-11-14T17:22:52Z INF Requesting new quick Tunnel on trycloudflare.com...
        2026-11-14T17:22:58Z INF +--------------------------------------------------------------------------------------------+
        2026-11-14T17:22:58Z INF |  Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):  |
        2026-11-14T17:22:58Z INF |  https://pump-trading-tiny-opposition.trycloudflare.com                                    |
        2026-11-14T17:22:58Z INF +--------------------------------------------------------------------------------------------+
        """
        let extracted = TunnelService.extractTunnelURL(from: sampleLog)
        XCTAssertEqual(extracted, "https://pump-trading-tiny-opposition.trycloudflare.com")
    }

    func testBuildProcessArgumentsForHTTPAndViteHostHeader() {
        let args = TunnelService.buildProcessArguments(port: "5173", isSSL: false, hostHeader: "localhost")
        XCTAssertEqual(args, [
            "tunnel",
            "--url", "http://127.0.0.1:5173",
            "--no-autoupdate",
            "--http-host-header", "localhost"
        ])
    }

    func testBuildProcessArgumentsForHTTPSVHostWithNoTLSVerify() {
        let args = TunnelService.buildProcessArguments(port: "8082", isSSL: true, hostHeader: "my-secure.test")
        XCTAssertEqual(args, [
            "tunnel",
            "--url", "https://127.0.0.1:8082",
            "--no-autoupdate",
            "--no-tls-verify",
            "--http-host-header", "my-secure.test"
        ])
    }

    func testBinaryDiscoveryChecksMultipleLocations() {
        let path = TunnelService.findBinaryPath()
        if let path = path {
            XCTAssertTrue(path.contains("cloudflared"))
        } else {
            XCTAssertFalse(TunnelService.isCloudflaredInstalled())
        }
    }

    @MainActor
    func testAppStateTunnelLifecycleMethods() async {
        let appState = AppState(autoRefreshOnInit: false)
        appState.checkCloudflaredInstallation()
        XCTAssertEqual(appState.isCloudflaredInstalled, TunnelService.isCloudflaredInstalled())

        let testId = "9999_test-unit"
        appState.activeTunnels[testId] = ActiveTunnel(port: "9999", label: "test-unit", status: .active)
        XCTAssertEqual(appState.activeTunnels.count, 1)

        appState.stopTunnel(tunnelId: testId)
        XCTAssertNil(appState.activeTunnels[testId])
    }

    @MainActor
    func testActiveTunnelTransitionsToErrorOnUnexpectedTermination() {
        let appState = AppState(autoRefreshOnInit: false)
        let testId = "9998_crash-test"
        appState.activeTunnels[testId] = ActiveTunnel(port: "9998", label: "crash-test", status: .active)

        appState.handleTunnelExit(tunnelId: testId, exitCode: 2)

        XCTAssertNotNil(appState.activeTunnels[testId])
        XCTAssertEqual(appState.activeTunnels[testId]?.status, .error)
        XCTAssertTrue(appState.activeTunnels[testId]?.errorMessage?.contains("Tunnel disconnected unexpectedly (exit code 2)") == true)
    }
}
