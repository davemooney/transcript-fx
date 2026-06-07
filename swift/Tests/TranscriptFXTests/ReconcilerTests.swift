import XCTest
@testable import TranscriptFX

final class ReconcilerTests: XCTestCase {
    private func snap(_ r: TranscriptReconciler) -> [String] {
        r.tokens.map { "\($0.text)/\($0.state == .final ? "final" : "volatile")" }
    }

    func testSingleSourceStreaming() {
        let r = TranscriptReconciler()
        r.ingest(ASRResult(words: [ASRWord(text: "set"), ASRWord(text: "a")], isFinal: false))
        let id0 = r.tokens[0].id
        r.ingest(ASRResult(words: [ASRWord(text: "said"), ASRWord(text: "a")], isFinal: false))
        XCTAssertEqual(r.tokens[0].id, id0)
        r.ingest(ASRResult(words: [ASRWord(text: "said"), ASRWord(text: "a"), ASRWord(text: "timer")], isFinal: true))
        XCTAssertEqual(snap(r), ["said/final", "a/final", "timer/final"])
    }

    func testTwoSourceTimeAlign() {
        let r = TranscriptReconciler()
        r.ingest(ASRResult(words: [
            ASRWord(text: "their", start: 0, end: 0.4),
            ASRWord(text: "meeting", start: 0.4, end: 0.8),
            ASRWord(text: "is", start: 0.8, end: 1.0),
        ], isFinal: false), role: .draft)
        let id0 = r.tokens[0].id
        r.ingest(ASRResult(words: [
            ASRWord(text: "there", start: 0, end: 0.4, confidence: 0.98),
            ASRWord(text: "meeting", start: 0.4, end: 0.8, confidence: 0.98),
            ASRWord(text: "is", start: 0.8, end: 1.0, confidence: 0.98),
        ], isFinal: true), role: .refined)
        XCTAssertEqual(snap(r), ["there/final", "meeting/final", "is/final"])
        XCTAssertEqual(r.tokens[0].id, id0)
    }

    func testRefinerDeletion() {
        let r = TranscriptReconciler()
        r.ingest(ASRResult(words: [
            ASRWord(text: "the", start: 0, end: 0.3),
            ASRWord(text: "quick", start: 0.3, end: 0.6),
            ASRWord(text: "brownn", start: 0.6, end: 0.9),
        ], isFinal: false), role: .draft)
        r.ingest(ASRResult(words: [
            ASRWord(text: "the", start: 0, end: 0.3, confidence: 0.95),
            ASRWord(text: "quick", start: 0.3, end: 0.6, confidence: 0.95),
        ], isFinal: false), role: .refined)
        XCTAssertEqual(r.tokens.map { $0.text }, ["the", "quick"])
    }

    func testNoTimestampFallback() {
        let r = TranscriptReconciler()
        r.ingest(ASRResult(transcript: "lets meat at too", isFinal: false), role: .draft)
        r.ingest(ASRResult(transcript: "let's meet at two", isFinal: true), role: .refined)
        XCTAssertEqual(snap(r), ["let's/final", "meet/final", "at/final", "two/final"])
    }
}
