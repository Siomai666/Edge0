import XCTest
@testable import LucyCore

final class SpeechChunkerTests: XCTestCase {
    func testEmitsCompletedSentencesIncrementally() {
        var c = SpeechChunker()
        XCTAssertEqual(c.take(from: "Hello there. How", final: false), ["Hello there."])
        XCTAssertEqual(c.take(from: "Hello there. How are you? I", final: false), ["How are you?"])
        XCTAssertEqual(c.take(from: "Hello there. How are you? I am fine", final: true), ["I am fine"])
    }

    func testDoesNotSplitDecimals() {
        var c = SpeechChunker()
        XCTAssertEqual(c.take(from: "It took 3.5 hours", final: false), [])
        XCTAssertEqual(c.take(from: "It took 3.5 hours.", final: true), ["It took 3.5 hours."])
    }

    func testNewlineEndsChunkAndBlankChunksAreDropped() {
        var c = SpeechChunker()
        XCTAssertEqual(c.take(from: "Line one\n\nLine two\n", final: false), ["Line one", "Line two"])
    }

    func testShrunkTextResets() {
        var c = SpeechChunker()
        _ = c.take(from: "Long sentence here. ", final: false)
        XCTAssertEqual(c.take(from: "New.", final: true), ["New."])
    }

    func testCleanStripsMarkdown() {
        XCTAssertEqual(SpeechText.clean("**Bold** and `code` # Title - item"), "Bold and code Title item")
        XCTAssertEqual(SpeechText.clean("  ***  "), "")
    }
}
