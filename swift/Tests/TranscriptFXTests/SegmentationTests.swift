import XCTest
@testable import TranscriptFX

final class SegmentationTests: XCTestCase {
    func testSentenceBreakOnPunctuation() {
        let r = TranscriptReconciler()
        let events = r.apply(TranscriptUpdate(text: "Hello there. How are you", isFinal: false))

        let paragraphs = r.snapshot.paragraphs
        XCTAssertEqual(paragraphs.count, 1)
        XCTAssertEqual(paragraphs[0].sentences.count, 2)
        XCTAssertEqual(paragraphs[0].sentences[0].tokens.map(\.text), ["Hello", "there."])
        XCTAssertEqual(paragraphs[0].sentences[1].tokens.map(\.text), ["How", "are", "you"])

        let periodID = r.snapshot.tokens[1].id
        XCTAssertTrue(events.contains(.sentenceBreak(afterID: periodID)))
    }

    func testUtteranceEndClosesSentenceOnlyWhenUtteranceCloses() {
        let r = TranscriptReconciler()
        r.apply(TranscriptUpdate(text: "no punctuation here"))
        XCTAssertEqual(r.snapshot.paragraphs[0].sentences.count, 1)

        // While streaming, no utterance-end sentence break yet.
        let lastID = r.snapshot.tokens.last!.id
        XCTAssertFalse(r.apply(TranscriptUpdate(text: "no punctuation here")).contains(.sentenceBreak(afterID: lastID)))

        let events = r.apply(TranscriptUpdate(text: "no punctuation here", isFinal: true))
        XCTAssertTrue(events.contains(.sentenceBreak(afterID: lastID)))
    }

    func testParagraphBreakOnSpeakerChange() {
        let r = TranscriptReconciler()
        r.apply(TranscriptUpdate(text: "first speaker talks", isFinal: true, speaker: "alice"))
        let lastAliceID = r.snapshot.tokens.last!.id
        let events = r.apply(TranscriptUpdate(text: "second speaker answers", speaker: "bob"))

        XCTAssertEqual(r.snapshot.paragraphs.count, 2)
        XCTAssertEqual(r.snapshot.paragraphs[0].speaker, "alice")
        XCTAssertEqual(r.snapshot.paragraphs[1].speaker, "bob")
        XCTAssertTrue(events.contains(.paragraphBreak(afterID: lastAliceID)))
    }

    func testParagraphBreakOnLongPause() {
        let r = TranscriptReconciler()
        r.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "before", start: 0, end: 0.5),
        ], isFinal: true))
        r.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "after", start: 5.0, end: 5.5),
        ]))

        XCTAssertEqual(r.snapshot.paragraphs.count, 2)
    }

    func testNoParagraphBreakWithinShortPauseSameSpeaker() {
        let r = TranscriptReconciler()
        r.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "quick", start: 0, end: 0.5),
        ], isFinal: true, speaker: "alice"))
        r.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "follow-up", start: 1.0, end: 1.5),
        ], speaker: "alice"))

        XCTAssertEqual(r.snapshot.paragraphs.count, 1)
    }

    func testCustomSegmentationPolicy() {
        var config = ReconcilerConfiguration()
        config.segmentation = SegmentationPolicy(paragraphPause: 0.3, paragraphOnSpeakerChange: false)
        let r = TranscriptReconciler(configuration: config)
        r.apply(TranscriptUpdate(words: [TranscriptWord(text: "a", start: 0, end: 0.1)], isFinal: true, speaker: "x"))
        r.apply(TranscriptUpdate(words: [TranscriptWord(text: "b", start: 0.6, end: 0.7)], speaker: "y"))

        // Speaker change ignored, but the 0.5s gap exceeds the 0.3s pause.
        XCTAssertEqual(r.snapshot.paragraphs.count, 2)
    }

    func testSnapshotPlainText() {
        let r = TranscriptReconciler()
        r.apply(TranscriptUpdate(text: "Hello there.", isFinal: true, speaker: "a"))
        r.apply(TranscriptUpdate(text: "Hi.", isFinal: true, speaker: "b"))
        XCTAssertEqual(r.snapshot.text, "Hello there.\n\nHi.")
    }
}
