import XCTest
@testable import TranscriptFX

final class AdapterTests: XCTestCase {
    struct MockWT: WhisperWordTiming {
        var word: String
        var start: Float
        var end: Float
        var probability: Float
    }

    func testWhisperKitMapping() {
        let words = [
            MockWT(word: " Hello", start: 0, end: 0.5, probability: 0.9),
            MockWT(word: " world", start: 0.5, end: 1.0, probability: 0.8),
        ]
        let asr = whisperKitToASR(words, isFinal: true)
        XCTAssertEqual(asr.words?.map { $0.text }, ["Hello", "world"]) // leading space trimmed
        XCTAssertEqual(asr.words![0].start, 0)
        XCTAssertEqual(asr.words![0].confidence!, 0.9, accuracy: 1e-6)
        XCTAssertTrue(asr.isFinal)
    }

    func testAppleSegmentMapping() {
        let segs: [(text: String, timestamp: Double, duration: Double, confidence: Float)] = [
            ("their", 0.0, 0.4, 0.5),
            ("meeting", 0.4, 0.5, 0.8),
        ]
        let asr = appleSegmentsToASR(segs, isFinal: false)
        XCTAssertEqual(asr.words?.map { $0.text }, ["their", "meeting"])
        XCTAssertEqual(asr.words![1].end!, 0.9, accuracy: 1e-6)
        XCTAssertFalse(asr.isFinal)
    }

    /// End-to-end: a fast draft, then a WhisperKit refine, through the reconciler.
    func testDraftThenWhisperRefine() {
        let r = TranscriptReconciler()
        r.ingest(ASRResult(words: [ASRWord(text: "too", start: 0, end: 0.4, confidence: 0.4)], isFinal: false), role: .draft)
        let refined = [MockWT(word: " two", start: 0, end: 0.4, probability: 0.97)]
        r.ingest(whisperKitToASR(refined, isFinal: true), role: .refined)
        XCTAssertEqual(r.tokens.map { $0.text }, ["two"])
        XCTAssertEqual(r.tokens[0].state, .final)
    }
}
