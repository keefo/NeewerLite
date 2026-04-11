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

    func test_LightName() throws {
        // This is an example of a functional test case.
        
        var name = NeewerLightConstant.getLightNames(rawName: "NEEWER-RGB660 PRO", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "RGB660 PRO-E4B053")
        XCTAssertEqual(name.projectName, "RGB660 PRO")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 3, "")
        
        name = NeewerLightConstant.getLightNames(rawName: "GR18C-953999", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "GR18C-953999-E4B053")
        XCTAssertEqual(name.projectName, "GR18C-953999")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 62, "")
        
        name = NeewerLightConstant.getLightNames(rawName: "NEEWER-GL1", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "GL1-E4B053")
        XCTAssertEqual(name.projectName, "GL1")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 4, "")

        name = NeewerLightConstant.getLightNames(rawName: "NEEWER-GL1 PRO", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "GL1 PRO-E4B053")
        XCTAssertEqual(name.projectName, "GL1 PRO")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 33, "")

        name = NeewerLightConstant.getLightNames(rawName: "NEEWER-GL1C", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "GL1C-E4B053")
        XCTAssertEqual(name.projectName, "GL1C")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 39, "")

        name = NeewerLightConstant.getLightNames(rawName: "NEEWER-RGB480", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "RGB480-E4B053")
        XCTAssertEqual(name.projectName, "RGB480")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 3, "")

        name = NeewerLightConstant.getLightNames(rawName: "NEEWER-RGB960", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "RGB960-E4B053")
        XCTAssertEqual(name.projectName, "RGB960")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 12, "")

        name = NeewerLightConstant.getLightNames(rawName: "NEEWER-SNL660", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "SNL660-E4B053")
        XCTAssertEqual(name.projectName, "SNL660")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 7, "")

        name = NeewerLightConstant.getLightNames(rawName: "NEEWER-SL80", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "SL80-E4B053")
        XCTAssertEqual(name.projectName, "SL80")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 6, "")

        name = NeewerLightConstant.getLightNames(rawName: "NEEWER-SL140", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "SL140-E4B053")
        XCTAssertEqual(name.projectName, "SL140")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 6, "") // Color Temperature: 2500K-9000K

        name = NeewerLightConstant.getLightNames(rawName: "NEEWER-NL-116AI", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "NL-116AI-E4B053")
        XCTAssertEqual(name.projectName, "NL-116AI")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 2, "")

        name = NeewerLightConstant.getLightNames(rawName: "NW-20210012&FFFFFFFF", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "CB60 RGB-E4B053")
        XCTAssertEqual(name.projectName, "CB60 RGB")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 22, "")

        name = NeewerLightConstant.getLightNames(rawName: "NW-20200015&6C9E0100", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "RGB1-E4B053")
        XCTAssertEqual(name.projectName, "RGB1")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 8, "")

        name = NeewerLightConstant.getLightNames(rawName: "NEEWER-SNL530", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "SNL530-E4B053")
        XCTAssertEqual(name.projectName, "SNL530")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 7, "")

        name = NeewerLightConstant.getLightNames(rawName: "NEEWER-RGB168", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "RGB168-E4B053")
        XCTAssertEqual(name.projectName, "RGB168")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 16, "")

        name = NeewerLightConstant.getLightNames(rawName: "NW-20200015&00000000", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "RGB1-E4B053")
        XCTAssertEqual(name.projectName, "RGB1")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 8, "")

        name = NeewerLightConstant.getLightNames(rawName: "NW-20220057&00000000", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "SL90 Pro-E4B053")
        XCTAssertEqual(name.projectName, "SL90 Pro")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 34, "")

        name = NeewerLightConstant.getLightNames(rawName: "NW-20210006&00000000", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "Apollo 150D-E4B053")
        XCTAssertEqual(name.projectName, "Apollo 150D")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 24, "")

        name = NeewerLightConstant.getLightNames(rawName: "NW-RGB176 A1", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "RGB176 A1-E4B053")
        XCTAssertEqual(name.projectName, "RGB176 A1")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 20, "")

        name = NeewerLightConstant.getLightNames(rawName: "NEEWER-RGB176", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-F0CC23BACB1C")
        XCTAssertEqual(name.nickName, "RGB176-BACB1C")
        XCTAssertEqual(name.projectName, "RGB176")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 5, "")

        name = NeewerLightConstant.getLightNames(rawName: "NEEWER-RGB530", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "RGB530-E4B053")
        XCTAssertEqual(name.projectName, "RGB530")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 3, "")

        name = NeewerLightConstant.getLightNames(rawName: "NEEWER-RGB530 Pro", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "RGB530 Pro-E4B053")
        XCTAssertEqual(name.projectName, "RGB530 Pro")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 3, "")

        name = NeewerLightConstant.getLightNames(rawName: "NW-20230021&00000000", identifier: "2EF9C9E1-275A-7278-44AC-86A4D03D69EC")
        XCTAssertEqual(name.nickName, "BH-30S RGB-3D69EC")
        XCTAssertEqual(name.projectName, "BH-30S RGB")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 26, "")

        name = NeewerLightConstant.getLightNames(rawName: "NW-20230021&00000000", identifier: "2EF9C9E1-275A-7278-44AC-86A4D03D69EC")
        XCTAssertEqual(name.nickName, "BH-30S RGB-3D69EC")
        XCTAssertEqual(name.projectName, "BH-30S RGB")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "NW-20230021&00000000", projectName: name.projectName), 42, "")
        
        name = NeewerLightConstant.getLightNames(rawName: "NW-20220014&00000000", identifier: "DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
        XCTAssertEqual(name.nickName, "CB60B-E4B053")
        XCTAssertEqual(name.projectName, "CB60B")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "", projectName: name.projectName), 31, "")
        
        name = NeewerLightConstant.getLightNames(rawName: "NW-20240073&00000000", identifier: "FCCD4ADF-1AD1-72B7-485D-39061E3686F0")
        XCTAssertEqual(name.nickName, "SL90-3686F0")
        XCTAssertEqual(name.projectName, "SL90")
        XCTAssertEqual(NeewerLightConstant.getLightType(nickName: name.nickName, rawname: "NW-20240073&00000000", projectName: name.projectName), 71, "")
    }

    func test_fxCommand() throws {
        let fxx = NeewerLightFX.lightingScene()
        let light = NeewerLight([:])
        light.supportedFX.append(fxx)
        let cmd = light.getSceneCommand("DF:24:3A:B4:46:5D", fxx)
        print("cmd: \(cmd)")
    }
    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
