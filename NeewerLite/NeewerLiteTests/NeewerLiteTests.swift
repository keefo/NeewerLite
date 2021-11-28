//
//  NeewerLiteTests.swift
//  NeewerLiteTests
//
//  Created by Xu Lian on 1/5/21.
//

import XCTest
@testable import NeewerLite

class NeewerLiteTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func test_getLightTypeByName() throws {
        // This is an example of a functional test case.
        XCTAssertEqual(NeewerLight.getLightTypeByName("NEEWER-RGB660 PRO"), 3, "")
        XCTAssertEqual(NeewerLight.getLightTypeByName("NEEWER-RGB480 PRO"), 3, "")
        XCTAssertEqual(NeewerLight.getLightTypeByName("NEEWER-SL80-RGB"), 3, "")
        XCTAssertEqual(NeewerLight.getLightTypeByName("NEEWER-RGB520"), 3, "")
        XCTAssertEqual(NeewerLight.getLightTypeByName("NEEWER-RGB960"), 12, "")
        XCTAssertEqual(NeewerLight.getLightTypeByName("NEEWER-SNL660"), 7, "")
        XCTAssertEqual(NeewerLight.getLightTypeByName("NEEWER-SL80"), 6, "")
        XCTAssertEqual(NeewerLight.getLightTypeByName("NEEWER-SL140"), 6, "") // Color Temperature: 2500K-9000K
        XCTAssertEqual(NeewerLight.getLightTypeByName("NEEWER-NL-116AI"), 2, "")
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
