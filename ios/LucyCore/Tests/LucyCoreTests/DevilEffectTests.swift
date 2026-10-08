import XCTest
@testable import LucyCore

final class DevilEffectTests: XCTestCase {
    func testZeroStrengthIsNeutral() {
        XCTAssertEqual(DevilEffect.parameters(strength: 0),
                       DevilEffectParameters(pitchCents: 0, distortionWetDryMix: 0, reverbWetDryMix: 0))
        XCTAssertFalse(DevilEffect.isActive(strength: 0))
    }

    func testFullStrengthHitsMaximums() {
        XCTAssertEqual(DevilEffect.parameters(strength: 1),
                       DevilEffectParameters(pitchCents: -700, distortionWetDryMix: 25, reverbWetDryMix: 30))
        XCTAssertTrue(DevilEffect.isActive(strength: 1))
    }

    func testHalfStrengthScalesLinearly() {
        let p = DevilEffect.parameters(strength: 0.5)
        XCTAssertEqual(p.pitchCents, -350, accuracy: 0.001)
        XCTAssertEqual(p.distortionWetDryMix, 12.5, accuracy: 0.001)
        XCTAssertEqual(p.reverbWetDryMix, 15, accuracy: 0.001)
    }

    func testOutOfRangeStrengthIsClamped() {
        XCTAssertEqual(DevilEffect.parameters(strength: 3), DevilEffect.parameters(strength: 1))
        XCTAssertEqual(DevilEffect.parameters(strength: -2), DevilEffect.parameters(strength: 0))
    }

    func testDefaultIsAudible() {
        XCTAssertTrue(DevilEffect.isActive(strength: DevilEffect.defaultStrength))
    }
}
