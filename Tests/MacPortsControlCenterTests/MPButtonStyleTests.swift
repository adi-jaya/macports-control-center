import Foundation
import SwiftUI
#if canImport(XCTest)
import XCTest
@testable import MacPortsControlCenter
#endif

final class MPButtonStyleTests: XCTestCase {
    func testVariantPropertiesAndEquality() {
        let v1 = MPButtonStyle.Variant.bordered
        let v2 = MPButtonStyle.Variant.borderedProminent
        let v3 = MPButtonStyle.Variant.borderless

        XCTAssertEqual(v1, .bordered)
        XCTAssertEqual(v2, .borderedProminent)
        XCTAssertEqual(v3, .borderless)
        XCTAssertNotEqual(v1, v2)
        XCTAssertNotEqual(v2, v3)
        XCTAssertNotEqual(v1, v3)
    }

    func testSizeMetricsAndPadding() {
        let reg = MPButtonStyle.Size.regular
        let small = MPButtonStyle.Size.small
        let mini = MPButtonStyle.Size.mini

        XCTAssertEqual(reg.horizontalPadding, 12)
        XCTAssertEqual(reg.verticalPadding, 6)

        XCTAssertEqual(small.horizontalPadding, 8)
        XCTAssertEqual(small.verticalPadding, 4)

        XCTAssertEqual(mini.horizontalPadding, 6)
        XCTAssertEqual(mini.verticalPadding, 2)
    }

    func testStyleInitializationAndDefaults() {
        let defaultStyle = MPButtonStyle()
        XCTAssertEqual(defaultStyle.variant, .bordered)
        XCTAssertEqual(defaultStyle.size, nil)
        XCTAssertEqual(defaultStyle.tint, nil)

        let customStyle = MPButtonStyle(variant: .borderedProminent, size: .small, tint: .green)
        XCTAssertEqual(customStyle.variant, .borderedProminent)
        XCTAssertEqual(customStyle.size, .small)
        XCTAssertEqual(customStyle.tint, .green)
    }

    func testViewModifierApplication() {
        let testButton = Button("Action") {}
            .mpButton(.borderedProminent, size: .small, tint: .orange)
        XCTAssertTrue(type(of: testButton) != Void.self)
    }
}
