import XCTest
@testable import TranscriptFX

final class AdapterTests: XCTestCase {
    struct MockWT: WhisperWordTiming {
        var word: String
        var start: Float
        var end: Float
        var probability: Float
    }

    func testWhisperKitMappingDefaultsToRefinedTier() {
        let words = [
            MockWT(word: " Hello", start: 0, end: 0.5, probability: 0.9),
            MockWT(word: " world", start: 0.5, end: 1.0, probability: 0.8),
        ]
        let update = whisperKitToUpdate(words, isFinal: true)

        XCTAssertEqual(update.words.map(\.text), ["Hello", "world"]) // leading space trimmed
        XCTAssertEqual(update.words[0].start, 0)
        XCTAssertEqual(update.words[0].confidence!, 0.9, accuracy: 1e-6)
        XCTAssertEqual(update.tier, .refined)
        XCTAssertTrue(update.isFinal)
    }

    func testAppleSegmentMapping() {
        let segments: [(text: String, timestamp: Double, duration: Double, confidence: Float)] = [
            ("their", 0.0, 0.4, 0.5),
            ("meeting", 0.4, 0.5, 0.8),
        ]
        let update = appleSegmentsToUpdate(segments, isFinal: false)

        XCTAssertEqual(update.words.map(\.text), ["their", "meeting"])
        XCTAssertEqual(update.words[1].end!, 0.9, accuracy: 1e-6)
        XCTAssertEqual(update.tier, .preview)
        XCTAssertFalse(update.isFinal)
    }

    func testDeepgramMappingCarriesDiarizedSpeakers() throws {
        let json = """
        {"channel":{"alternatives":[{"transcript":"hi there","confidence":0.9,"words":[
            {"word":"hi","punctuated_word":"Hi","confidence":0.9,"start":0.0,"end":0.3,"speaker":0},
            {"word":"there","confidence":0.8,"start":0.3,"end":0.6,"speaker":1}
        ]}]},"is_final":true}
        """
        let update = try XCTUnwrap(deepgramToUpdate(jsonData: Data(json.utf8)))

        XCTAssertEqual(update.words.map(\.text), ["Hi", "there"]) // punctuated_word preferred
        XCTAssertEqual(update.words.map(\.speaker), [SpeakerID("0"), SpeakerID("1")])
        XCTAssertTrue(update.isFinal)
    }

    /// End-to-end: a fast preview, then a WhisperKit refinement, through the
    /// full reconciler.
    func testPreviewThenWhisperRefinement() {
        let r = TranscriptReconciler(configuration: .twoTier)
        r.apply(TranscriptUpdate(words: [TranscriptWord(text: "too", start: 0, end: 0.4, confidence: 0.4)], isFinal: true))
        let id0 = r.snapshot.tokens[0].id

        let refined = [MockWT(word: " two", start: 0, end: 0.4, probability: 0.97)]
        r.apply(whisperKitToUpdate(refined, isFinal: true))

        XCTAssertEqual(r.snapshot.tokens.map(\.text), ["two"])
        XCTAssertEqual(r.snapshot.tokens[0].id, id0)
        XCTAssertEqual(r.snapshot.tokens[0].state, .finalized)
    }
}
