//
//  StringLocalizedTests.swift
//  NeewerLiteTests
//
//  Created by Xu Lian on 4/18/26.
//

import XCTest
@testable import NeewerLite

final class StringLocalizedTests: XCTestCase {

    // MARK: - localized (property)

    func test_localized_returnsOriginalForUnknownKey() {
        // NSLocalizedString returns the key itself when no translation exists
        let key = "__nonexistent_key_\(UUID().uuidString)__"
        XCTAssertEqual(key.localized, key)
    }

    func test_localized_returnsStringForKnownKey() {
        // In the test bundle the base language is English, so a key that
        // exists in Localizable.xcstrings should come back as a non-empty
        // string (either its English value or the key itself).
        let result = "Brightness".localized
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - localized(comment:)

    func test_localizedWithComment_returnsOriginalForUnknownKey() {
        let key = "__nonexistent_key_\(UUID().uuidString)__"
        XCTAssertEqual(key.localized(comment: "test comment"), key)
    }

    func test_localizedWithComment_returnsStringForKnownKey() {
        let result = "Brightness".localized(comment: "digital readout header")
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - localized(_ args:) with format strings

    func test_localizedArgs_oneArg() {
        // "%@ connected" style — when the key is not found, NSLocalizedString
        // returns the key as the format string.
        let fmt = "%@ connected"
        let result = fmt.localized("Light1")
        XCTAssertEqual(result, "Light1 connected")
    }

    func test_localizedArgs_twoArgs() {
        let fmt = "%@ %@"
        let result = fmt.localized("Hello", "World")
        XCTAssertEqual(result, "Hello World")
    }

    func test_localizedArgs_threeArgs() {
        let fmt = "%@-%@-%@"
        let result = fmt.localized("A", "B", "C")
        XCTAssertEqual(result, "A-B-C")
    }

    func test_localizedArgs_fourArgs() {
        let fmt = "%@ %@ %@ %@"
        let result = fmt.localized("1", "2", "3", "4")
        XCTAssertEqual(result, "1 2 3 4")
    }

    func test_localizedArgs_fiveArgs() {
        let fmt = "%@.%@.%@.%@.%@"
        let result = fmt.localized("a", "b", "c", "d", "e")
        XCTAssertEqual(result, "a.b.c.d.e")
    }

    func test_localizedArgs_zeroArgs_returnsFormat() {
        let fmt = "No args here"
        let result = fmt.localized() as String
        XCTAssertEqual(result, "No args here")
    }

    func test_localizedArgs_moreThanFive_returnsFormatUnchanged() {
        // The switch default branch returns the format without substitution
        let fmt = "%@ %@ %@ %@ %@ %@"
        let result = fmt.localized("1", "2", "3", "4", "5", "6")
        XCTAssertEqual(result, "%@ %@ %@ %@ %@ %@")
    }

    func test_localizedArgs_integerFormat() {
        let fmt = "Count: %d"
        let result = fmt.localized(42)
        XCTAssertEqual(result, "Count: 42")
    }
}
