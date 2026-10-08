import XCTest
@testable import LucyCore

final class PersonaTests: XCTestCase {
    func testLucyPromptIsShortAndInCharacter() {
        let prompt = Persona(preset: .lucyTyrant, userName: "").systemPrompt()
        XCTAssertTrue(prompt.contains("Lucy"))
        XCTAssertTrue(prompt.contains("tyrant"))
        XCTAssertTrue(prompt.contains("serious mode"))
        XCTAssertLessThanOrEqual(TokenEstimate.approximate(prompt), 80)
    }

    func testUserNameIsIncludedAndTruncated() {
        let long = String(repeating: "x", count: 100)
        let prompt = Persona(preset: .lucyTyrant, userName: "  \(long)  ").systemPrompt()
        XCTAssertTrue(prompt.contains(String(repeating: "x", count: 40)))
        XCTAssertFalse(prompt.contains(String(repeating: "x", count: 41)))
    }

    func testBlankUserNameIsOmitted() {
        XCTAssertFalse(Persona(preset: .buddy, userName: "   ").systemPrompt().contains("user's name"))
    }

    func testEveryPresetFitsBudget() {
        for preset in PersonaPreset.allCases {
            let prompt = Persona(preset: preset, userName: String(repeating: "n", count: 40)).systemPrompt()
            XCTAssertLessThanOrEqual(TokenEstimate.approximate(prompt), Persona.tokenBudget, "\(preset)")
            XCTAssertFalse(preset.title.isEmpty)
            XCTAssertFalse(preset.sampleLine.isEmpty)
            XCTAssertTrue((0.5...2.0).contains(preset.pitch))
            XCTAssertTrue((0.0...1.0).contains(preset.rate))
        }
    }

    func testTokenEstimateRoundsUp() {
        XCTAssertEqual(TokenEstimate.approximate(""), 0)
        XCTAssertEqual(TokenEstimate.approximate("abcde"), 2)
    }
}
