import XCTest
@testable import LucyCore

final class VoiceStyleTests: XCTestCase {
    func testVillainQueenIsColdNotGrowly() {
        let e = VoiceStyle.villainQueen.effect(strength: 1)
        XCTAssertEqual(e, VoiceEffectParameters(pitchCents: -150, distortionWetDryMix: 0, reverbWetDryMix: 22))
        XCTAssertEqual(VoiceStyle.villainQueen.preferredLanguage, "en-GB")
        XCTAssertLessThan(VoiceStyle.villainQueen.rate, VoiceStyle.plain.rate)
        XCTAssertEqual(VoiceStyle.defaultStyle, .villainQueen)
    }

    func testDemonKeepsTheOldDevilSound() {
        XCTAssertEqual(VoiceStyle.demon.effect(strength: 1),
                       VoiceEffectParameters(pitchCents: -700, distortionWetDryMix: 25, reverbWetDryMix: 30))
    }

    func testStrengthScalesAndClamps() {
        let half = VoiceStyle.demon.effect(strength: 0.5)
        XCTAssertEqual(half.pitchCents, -350, accuracy: 0.001)
        XCTAssertEqual(half.reverbWetDryMix, 15, accuracy: 0.001)
        XCTAssertEqual(VoiceStyle.demon.effect(strength: 4), VoiceStyle.demon.effect(strength: 1))
        XCTAssertEqual(VoiceStyle.demon.effect(strength: -1), .none)
    }

    func testAudibility() {
        XCTAssertFalse(VoiceStyle.plain.effect(strength: 1).isAudible)
        XCTAssertFalse(VoiceStyle.villainQueen.effect(strength: 0).isAudible)
        XCTAssertTrue(VoiceStyle.villainQueen.effect(strength: 0.5).isAudible)
    }

    func testEveryStyleHasSaneDelivery() {
        for style in VoiceStyle.allCases {
            XCTAssertFalse(style.title.isEmpty)
            XCTAssertTrue((0.5...2.0).contains(style.pitch), "\(style)")
            XCTAssertTrue((0.0...1.0).contains(style.rate), "\(style)")
        }
    }
}

final class VoicePickerTests: XCTestCase {
    private func v(_ id: String, _ lang: String, female: Bool = true, q: Int = 1,
                   personal: Bool = false) -> VoiceCandidate {
        VoiceCandidate(id: id, language: lang, isFemale: female, quality: q, isPersonal: personal)
    }

    func testPrefersBritishFemaleHighestQualityForVillainQueen() {
        let voices = [v("us-premium", "en-US", q: 3), v("gb-male", "en-GB", female: false, q: 3),
                      v("gb-default", "en-GB", q: 1), v("gb-enhanced", "en-GB", q: 2)]
        XCTAssertEqual(VoicePicker.pick(from: voices, style: .villainQueen), "gb-enhanced")
    }

    func testFallsBackToAnyEnglishWhenNoBritishVoice() {
        let voices = [v("fr", "fr-FR", q: 3), v("au", "en-AU", q: 2), v("in", "en-IN", q: 1)]
        XCTAssertEqual(VoicePicker.pick(from: voices, style: .villainQueen), "au")
    }

    func testNeverAutoPicksPersonalVoice() {
        let voices = [v("me", "en-GB", q: 3, personal: true), v("gb", "en-GB", q: 1)]
        XCTAssertEqual(VoicePicker.pick(from: voices, style: .villainQueen), "gb")
    }

    func testReturnsNilWithoutEnglishVoices() {
        XCTAssertNil(VoicePicker.pick(from: [v("zh", "zh-TW")], style: .plain))
    }

    func testTieBreaksDeterministicallyById() {
        let voices = [v("b", "en-US"), v("a", "en-US")]
        XCTAssertEqual(VoicePicker.pick(from: voices, style: .plain), "a")
    }
}
