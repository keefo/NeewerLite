//
//  GelsTests.swift
//  NeewerLiteTests
//
//  Created by Xu Lian on 4/10/26.
//

import XCTest
@testable import NeewerLite

final class GelsTests: XCTestCase {

    // MARK: - hsiToRGB

    func test_hsiToRGB_red() {
        let (r, g, b) = hsiToRGB(hue: 0, saturation: 1.0)
        XCTAssertEqual(r, 1.0, accuracy: 0.001)
        XCTAssertEqual(g, 0.0, accuracy: 0.001)
        XCTAssertEqual(b, 0.0, accuracy: 0.001)
    }

    func test_hsiToRGB_green() {
        let (r, g, b) = hsiToRGB(hue: 120, saturation: 1.0)
        XCTAssertEqual(r, 0.0, accuracy: 0.001)
        XCTAssertEqual(g, 1.0, accuracy: 0.001)
        XCTAssertEqual(b, 0.0, accuracy: 0.001)
    }

    func test_hsiToRGB_blue() {
        let (r, g, b) = hsiToRGB(hue: 240, saturation: 1.0)
        XCTAssertEqual(r, 0.0, accuracy: 0.001)
        XCTAssertEqual(g, 0.0, accuracy: 0.001)
        XCTAssertEqual(b, 1.0, accuracy: 0.001)
    }

    func test_hsiToRGB_white_is_unsaturated() {
        // Saturation 0 → all channels = 1 (white transmission)
        let (r, g, b) = hsiToRGB(hue: 0, saturation: 0.0)
        XCTAssertEqual(r, 1.0, accuracy: 0.001)
        XCTAssertEqual(g, 1.0, accuracy: 0.001)
        XCTAssertEqual(b, 1.0, accuracy: 0.001)
    }

    // MARK: - rgbToHS round-trip

    func test_rgbToHS_roundTrip_orange() {
        let inputHue = 30.0
        let inputSat = 0.6
        let rgb = hsiToRGB(hue: inputHue, saturation: inputSat)
        let (hue, sat) = rgbToHS(r: rgb.r, g: rgb.g, b: rgb.b)
        XCTAssertEqual(hue, inputHue, accuracy: 1.0,   "Hue round-trip failed")
        XCTAssertEqual(sat, inputSat, accuracy: 0.05,  "Saturation round-trip failed")
    }

    func test_rgbToHS_roundTrip_cyan() {
        let inputHue = 180.0
        let inputSat = 0.85
        let rgb = hsiToRGB(hue: inputHue, saturation: inputSat)
        let (hue, sat) = rgbToHS(r: rgb.r, g: rgb.g, b: rgb.b)
        XCTAssertEqual(hue, inputHue, accuracy: 1.0)
        XCTAssertEqual(sat, inputSat, accuracy: 0.05)
    }

    // MARK: - NeewerGel.stacked (subtractive mixing)

    func makeGel(id: String, hue: Double, sat: Double, transmission: Double, mireds: Double) -> NeewerGel {
        NeewerGel(
            id: id,
            name: id,
            hue: hue,
            saturation: sat,
            transmissionPercent: transmission,
            mireds: mireds,
            category: .colorCorrection,
            manufacturer: "",
            code: ""
        )
    }

    func test_stacked_transmission_compounds_multiplicatively() {
        let g1 = makeGel(id: "a", hue: 30, sat: 60, transmission: 80, mireds: 80)
        let g2 = makeGel(id: "b", hue: 30, sat: 60, transmission: 50, mireds: 80)
        let result = g1.stacked(with: g2)
        // 80% × 50% = 40%
        XCTAssertEqual(result.transmissionPercent, 40.0, accuracy: 0.01)
    }

    func test_stacked_mireds_add_linearly() {
        let g1 = makeGel(id: "cto-half",  hue: 30, sat: 38, transmission: 83, mireds: 80)
        let g2 = makeGel(id: "cto-half2", hue: 30, sat: 38, transmission: 83, mireds: 80)
        let result = g1.stacked(with: g2)
        // Two × ½ CTO = Full CTO (≈ 159 Mireds)
        XCTAssertEqual(result.mireds, 160.0, accuracy: 1.0)
    }

    func test_stacked_brightness_scale_clamps_to_1() {
        let g1 = makeGel(id: "dense", hue: 0, sat: 90, transmission: 200, mireds: 0) // >100 edge case
        let result = g1.stacked(with: g1)
        XCTAssertLessThanOrEqual(result.brightnessScale, 1.0)
    }

    func test_stacked_effectiveBrightness() {
        let g1 = makeGel(id: "g1", hue: 30, sat: 60, transmission: 80, mireds: 0)
        let g2 = makeGel(id: "g2", hue: 30, sat: 60, transmission: 50, mireds: 0)
        let result = g1.stacked(with: g2)
        // Transmission = 40% → effectiveBrightness(base: 100) = 40
        XCTAssertEqual(result.effectiveBrightness(base: 100), 40.0, accuracy: 0.1)
    }

    func test_single_gel_stackedResult() {
        let g1 = makeGel(id: "single", hue: 30, sat: 60, transmission: 68, mireds: 159)
        let gelState = GelState()
        gelState.activeGel = g1
        let result = gelState.stackedResult
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.hue, g1.hue, accuracy: 1.0)
        XCTAssertEqual(result!.saturation, g1.saturation, accuracy: 0.1)
        XCTAssertEqual(result!.transmissionPercent, g1.transmissionPercent, accuracy: 0.01)
    }

    func test_two_gels_stackedResult() {
        let g1 = makeGel(id: "g1", hue: 30, sat: 60, transmission: 80, mireds: 0)
        let g2 = makeGel(id: "g2", hue: 30, sat: 60, transmission: 50, mireds: 0)
        let gelState = GelState()
        gelState.activeGel = g1
        gelState.stackedGel = g2
        let result = gelState.stackedResult
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.transmissionPercent, 40.0, accuracy: 0.01)
        XCTAssertEqual(result!.sourceGels.count, 2)
    }

    func test_no_gel_stackedResult_is_nil() {
        let gelState = GelState()
        XCTAssertNil(gelState.stackedResult)
    }

    // MARK: - GelLibrary

    func test_gelLibrary_loads_builtin_presets() {
        let library = GelLibrary.shared
        XCTAssertFalse(library.all.isEmpty, "GelLibrary should load at least one preset from gels.json")
    }

    func test_gelLibrary_cc_category_contains_cto_full() {
        let ccGels = GelLibrary.shared.gels(in: .colorCorrection)
        let ctoFull = ccGels.first(where: { $0.id == "cto-full" })
        XCTAssertNotNil(ctoFull, "CTO Full must be present in the CC category")
        XCTAssertEqual(ctoFull!.hue, 30, accuracy: 0.1)
        XCTAssertEqual(ctoFull!.saturation, 60, accuracy: 0.1)
        XCTAssertEqual(ctoFull!.mireds, 159, accuracy: 0.1)
    }

    func test_gelLibrary_creative_category() {
        let creative = GelLibrary.shared.gels(in: .creative)
        XCTAssertFalse(creative.isEmpty, "Creative category must have at least one gel")
        // All returned gels should actually belong to .creative
        XCTAssertTrue(creative.allSatisfy { $0.category == .creative })
    }

    func test_gelLibrary_gel_lookup_by_id() {
        let gel = GelLibrary.shared.gel(id: "ctb-full")
        XCTAssertNotNil(gel)
        XCTAssertEqual(gel!.name, "CTB Full")
    }

    func test_gelLibrary_gel_lookup_by_manufacturer_code() {
        let gel = GelLibrary.shared.gel(manufacturer: "Lee", code: "204")
        XCTAssertNotNil(gel)
        XCTAssertEqual(gel!.id, "cto-full")
    }

    func test_gelLibrary_unknown_id_returns_nil() {
        XCTAssertNil(GelLibrary.shared.gel(id: "does-not-exist"))
    }

    // MARK: - NeewerGel.GelCategory decoding

    func test_gelCategory_decodes_from_json() throws {
        let json = """
        [{
          "id": "test-gel",
          "name": "Test",
          "hue": 30,
          "saturation": 20,
          "transmissionPercent": 90,
          "mireds": 40,
          "category": "CC",
          "manufacturer": "Lee",
          "code": "440"
        }]
        """.data(using: .utf8)!
        let gels = try JSONDecoder().decode([NeewerGel].self, from: json)
        XCTAssertEqual(gels.count, 1)
        XCTAssertEqual(gels[0].category, .colorCorrection)
        XCTAssertEqual(gels[0].id, "test-gel")
    }

    func test_gelCategory_invalid_throws() {
        let json = """
        [{
          "id": "bad",
          "name": "Bad",
          "hue": 0,
          "saturation": 0,
          "transmissionPercent": 100,
          "mireds": 0,
          "category": "INVALID",
          "manufacturer": "",
          "code": ""
        }]
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode([NeewerGel].self, from: json))
    }

    // MARK: - Clamped helper

    func test_clamped_belowRange() {
        XCTAssertEqual((-5.0).clamped(to: 0.0...1.0), 0.0)
    }

    func test_clamped_aboveRange() {
        XCTAssertEqual((1.5).clamped(to: 0.0...1.0), 1.0)
    }

    func test_clamped_withinRange() {
        XCTAssertEqual((0.6).clamped(to: 0.0...1.0), 0.6)
    }
}
