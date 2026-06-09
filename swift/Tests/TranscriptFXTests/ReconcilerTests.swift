import XCTest
@testable import TranscriptFX

final class ReconcilerTests: XCTestCase {
    private func texts(_ r: TranscriptReconciler) -> [String] {
        r.snapshot.tokens.map(\.text)
    }

    private func states(_ r: TranscriptReconciler) -> [TokenState] {
        r.snapshot.tokens.map(\.state)
    }

    // MARK: Preview tier

    func testPreviewStreamingRevisesInPlace() {
        let r = TranscriptReconciler()
        r.apply(TranscriptUpdate(words: [TranscriptWord(text: "set"), TranscriptWord(text: "a")]))
        let id0 = r.snapshot.tokens[0].id
        let events = r.apply(TranscriptUpdate(words: [TranscriptWord(text: "said"), TranscriptWord(text: "a"), TranscriptWord(text: "timer")]))

        XCTAssertEqual(texts(r), ["said", "a", "timer"])
        XCTAssertEqual(r.snapshot.tokens[0].id, id0, "interim correction must keep token identity")
        XCTAssertTrue(events.contains(.revise(id: id0, oldText: "set", newText: "said")))
        XCTAssertTrue(events.contains(.insert(id: r.snapshot.tokens[2].id, index: 2)))
    }

    func testPreviewShrinkEmitsRemove() {
        let r = TranscriptReconciler()
        r.apply(TranscriptUpdate(text: "the quick brownn"))
        let removedID = r.snapshot.tokens[2].id
        let events = r.apply(TranscriptUpdate(text: "the quick"))

        XCTAssertEqual(texts(r), ["the", "quick"])
        XCTAssertTrue(events.contains(.remove(id: removedID)))
    }

    func testPreviewFinalFinalizesUnderDefaultPolicy() {
        let r = TranscriptReconciler()
        r.apply(TranscriptUpdate(text: "hello world", isFinal: true))

        XCTAssertEqual(states(r), [.finalized, .finalized])

        // Next preview update opens a fresh utterance instead of touching it.
        r.apply(TranscriptUpdate(text: "again"))
        XCTAssertEqual(texts(r), ["hello", "world", "again"])
        XCTAssertEqual(states(r), [.finalized, .finalized, .provisional])
    }

    func testTwoTierPolicyKeepsPreviewFinalRevisable() {
        let r = TranscriptReconciler(configuration: .twoTier)
        let events = r.apply(TranscriptUpdate(text: "hello world", isFinal: true))

        XCTAssertEqual(states(r), [.provisional, .provisional])
        XCTAssertFalse(events.contains { if case .finalize = $0 { return true }; return false })

        let refinedEvents = r.apply(TranscriptUpdate(text: "hello world", tier: .refined, isFinal: true))
        XCTAssertEqual(states(r), [.finalized, .finalized])
        XCTAssertTrue(refinedEvents.contains { if case .finalize = $0 { return true }; return false })
    }

    // MARK: Refined tier — timestamp alignment

    func testRefinedTimeAlignedCorrectionKeepsIdentity() {
        let r = TranscriptReconciler()
        r.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "their", start: 0, end: 0.4, confidence: 0.5),
            TranscriptWord(text: "meeting", start: 0.4, end: 0.9, confidence: 0.7),
        ]))
        let id0 = r.snapshot.tokens[0].id

        let events = r.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "there", start: 0, end: 0.4, confidence: 0.98),
            TranscriptWord(text: "meeting", start: 0.4, end: 0.9, confidence: 0.98),
        ], tier: .refined, isFinal: true))

        XCTAssertEqual(texts(r), ["there", "meeting"])
        XCTAssertEqual(r.snapshot.tokens[0].id, id0)
        XCTAssertEqual(states(r), [.finalized, .finalized])
        XCTAssertTrue(events.contains(.revise(id: id0, oldText: "their", newText: "there")))
    }

    func testRefinedInsertAndRemove() {
        let r = TranscriptReconciler()
        r.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "the", start: 0, end: 0.3),
            TranscriptWord(text: "brownn", start: 0.6, end: 0.9),
        ]))
        let removedID = r.snapshot.tokens[1].id

        // Final refined pass = authoritative for the utterance: the trailing
        // hallucination is dropped even though no refined word overlaps it.
        let events = r.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "the", start: 0, end: 0.3, confidence: 0.95),
            TranscriptWord(text: "quick", start: 0.3, end: 0.6, confidence: 0.95),
        ], tier: .refined, isFinal: true))

        XCTAssertEqual(texts(r), ["the", "quick"])
        XCTAssertTrue(events.contains(.insert(id: r.snapshot.tokens[1].id, index: 1)))
        XCTAssertTrue(events.contains(.remove(id: removedID)))
        XCTAssertEqual(states(r), [.finalized, .finalized])
    }

    func testRefinedSplit() {
        let r = TranscriptReconciler()
        r.apply(TranscriptUpdate(words: [TranscriptWord(text: "gonna", start: 0, end: 0.5, confidence: 0.5)]))
        let id0 = r.snapshot.tokens[0].id

        let events = r.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "going", start: 0, end: 0.25, confidence: 0.97),
            TranscriptWord(text: "to", start: 0.25, end: 0.5, confidence: 0.97),
        ], tier: .refined))

        XCTAssertEqual(texts(r), ["going", "to"])
        XCTAssertEqual(r.snapshot.tokens[0].id, id0, "leading fragment keeps the original identity")
        XCTAssertTrue(events.contains(.split(id: id0, into: r.snapshot.tokens.map(\.id))))
    }

    func testRefinedMerge() {
        let r = TranscriptReconciler()
        r.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "two", start: 1.4, end: 1.8),
            TranscriptWord(text: "thirty", start: 1.8, end: 2.2),
        ]))
        let ids = r.snapshot.tokens.map(\.id)

        let events = r.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "2:30", start: 1.4, end: 2.2, confidence: 0.97),
        ], tier: .refined))

        XCTAssertEqual(texts(r), ["2:30"])
        XCTAssertEqual(r.snapshot.tokens[0].id, ids[0], "merged token keeps the first identity")
        XCTAssertTrue(events.contains(.merge(ids: ids, into: ids[0])))
    }

    func testRefinedLeavesTokensOutsideItsTimeSpanUntouched() {
        let r = TranscriptReconciler()
        r.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "their", start: 0, end: 0.4),
            TranscriptWord(text: "meeting", start: 0.4, end: 0.9),
            TranscriptWord(text: "today", start: 0.9, end: 1.3),
        ]))

        // Partial refinement covering only the first word.
        r.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "there", start: 0, end: 0.4, confidence: 0.98),
        ], tier: .refined))

        XCTAssertEqual(texts(r), ["there", "meeting", "today"])
        XCTAssertEqual(states(r), [.revised, .provisional, .provisional])
    }

    // MARK: Refined tier — text and positional alignment

    func testUntimedTextAlignmentKeepsIdentityOnCorrections() {
        let r = TranscriptReconciler()
        r.apply(TranscriptUpdate(text: "lets meat at too"))
        let ids = r.snapshot.tokens.map(\.id)

        r.apply(TranscriptUpdate(text: "let's meet at two.", tier: .refined, isFinal: true))

        XCTAssertEqual(texts(r), ["let's", "meet", "at", "two."])
        XCTAssertEqual(r.snapshot.tokens.map(\.id), ids, "corrections with shared letters keep identity")
        XCTAssertEqual(states(r), [.finalized, .finalized, .finalized, .finalized])
    }

    func testTextAlignmentReplacesWhenNoCharactersShared() {
        let r = TranscriptReconciler()
        r.apply(TranscriptUpdate(text: "the cue deck"))
        let cueID = r.snapshot.tokens[1].id

        let events = r.apply(TranscriptUpdate(text: "the Q3 deck", tier: .refined))

        XCTAssertEqual(texts(r), ["the", "Q3", "deck"])
        XCTAssertNotEqual(r.snapshot.tokens[1].id, cueID)
        XCTAssertTrue(events.contains(.replace(removedID: cueID, insertedID: r.snapshot.tokens[1].id)))
    }

    func testTextFirstPolicyIgnoresTimestamps() {
        let r = TranscriptReconciler(configuration: ReconcilerConfiguration(alignment: .textFirst))
        r.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "hello", start: 0, end: 0.5),
            TranscriptWord(text: "world", start: 0.5, end: 1.0),
        ]))
        let ids = r.snapshot.tokens.map(\.id)

        // Deliberately wrong timestamps; text alignment should still match.
        r.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "hello", start: 90, end: 90.5),
            TranscriptWord(text: "world", start: 90.5, end: 91),
        ], tier: .refined))

        XCTAssertEqual(r.snapshot.tokens.map(\.id), ids)
    }

    // MARK: Utterance targeting

    func testLateRefinementTargetsEarlierUtteranceByTime() {
        let r = TranscriptReconciler(configuration: .twoTier)
        // Utterance 1, preview-complete.
        r.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "their", start: 0, end: 0.4),
            TranscriptWord(text: "meeting", start: 0.4, end: 0.9),
        ], isFinal: true))
        // Utterance 2, still streaming.
        r.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "and", start: 3.0, end: 3.2),
            TranscriptWord(text: "now", start: 3.2, end: 3.4),
        ]))

        // Tier-2 lands for utterance 1 while utterance 2 streams.
        r.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "there", start: 0, end: 0.4, confidence: 0.98),
            TranscriptWord(text: "meeting", start: 0.4, end: 0.9, confidence: 0.98),
        ], tier: .refined, isFinal: true))

        XCTAssertEqual(texts(r), ["there", "meeting", "and", "now"])
        XCTAssertEqual(states(r), [.finalized, .finalized, .provisional, .provisional])
        XCTAssertTrue(r.snapshot.isLive, "utterance 2 must still be streaming")
    }

    func testRefinementTargetsUtteranceByExternalID() {
        let r = TranscriptReconciler(configuration: .twoTier)
        r.apply(TranscriptUpdate(text: "won", isFinal: true, utteranceID: "u-a"))
        r.apply(TranscriptUpdate(text: "to", isFinal: true, utteranceID: "u-b"))

        r.apply(TranscriptUpdate(text: "one", tier: .refined, isFinal: true, utteranceID: "u-a"))

        XCTAssertEqual(texts(r), ["one", "to"])
        XCTAssertEqual(states(r), [.finalized, .provisional])
    }

    func testRefinedOnlyStreamCreatesUtterance() {
        let r = TranscriptReconciler()
        r.apply(TranscriptUpdate(text: "straight to refined", tier: .refined, isFinal: true))
        XCTAssertEqual(texts(r), ["straight", "to", "refined"])
        XCTAssertEqual(states(r), [.finalized, .finalized, .finalized])
    }

    // MARK: Speakers

    func testSpeakerChangeEmitsEvent() {
        let r = TranscriptReconciler()
        r.apply(TranscriptUpdate(text: "hello there", speaker: "alice"))
        let id0 = r.snapshot.tokens[0].id

        let events = r.apply(TranscriptUpdate(
            words: [TranscriptWord(text: "hello"), TranscriptWord(text: "there")],
            tier: .refined,
            speaker: "bob"
        ))

        XCTAssertEqual(r.snapshot.tokens.map(\.speaker), [SpeakerID("bob"), SpeakerID("bob")])
        XCTAssertTrue(events.contains(.speakerChange(id: id0, from: "alice", to: "bob")))
    }

    func testWordLevelSpeakerOutranksUpdateSpeaker() {
        let r = TranscriptReconciler()
        r.apply(TranscriptUpdate(
            words: [TranscriptWord(text: "hi", speaker: "alice"), TranscriptWord(text: "yes")],
            speaker: "bob"
        ))
        XCTAssertEqual(r.snapshot.tokens.map(\.speaker), [SpeakerID("alice"), SpeakerID("bob")])
    }

    // MARK: Finalization & determinism

    func testFinalizeAllCommitsEverything() {
        let r = TranscriptReconciler(configuration: .twoTier)
        r.apply(TranscriptUpdate(text: "still going", isFinal: false))
        let events = r.finalizeAll()

        XCTAssertEqual(states(r), [.finalized, .finalized])
        XCTAssertFalse(r.snapshot.isLive)
        XCTAssertTrue(events.contains(.finalize(ids: r.snapshot.tokens.map(\.id))))
    }

    func testFinalizedTokensNeverChangeAgain() {
        let r = TranscriptReconciler()
        r.apply(TranscriptUpdate(text: "locked in", isFinal: true))
        r.apply(TranscriptUpdate(text: "changed up", tier: .refined, isFinal: true))

        // The refined update opens a new utterance; the finalized one is immutable.
        XCTAssertEqual(Array(texts(r).prefix(2)), ["locked", "in"])
    }

    func testDeterminism() {
        func run() -> ([String], [[RevisionEvent]]) {
            let r = TranscriptReconciler(configuration: .twoTier)
            var allEvents: [[RevisionEvent]] = []
            allEvents.append(r.apply(TranscriptUpdate(words: [
                TranscriptWord(text: "their", start: 0, end: 0.4, confidence: 0.5, speaker: "0"),
                TranscriptWord(text: "meeting", start: 0.4, end: 0.9, confidence: 0.7, speaker: "0"),
            ])))
            allEvents.append(r.apply(TranscriptUpdate(words: [
                TranscriptWord(text: "their", start: 0, end: 0.4, confidence: 0.5, speaker: "0"),
                TranscriptWord(text: "meeting", start: 0.4, end: 0.9, confidence: 0.7, speaker: "0"),
                TranscriptWord(text: "is", start: 0.9, end: 1.1, confidence: 0.6, speaker: "0"),
            ], isFinal: true)))
            allEvents.append(r.apply(TranscriptUpdate(words: [
                TranscriptWord(text: "there", start: 0, end: 0.4, confidence: 0.98, speaker: "0"),
                TranscriptWord(text: "meeting", start: 0.4, end: 0.9, confidence: 0.98, speaker: "0"),
                TranscriptWord(text: "is", start: 0.9, end: 1.1, confidence: 0.98, speaker: "0"),
            ], tier: .refined, isFinal: true)))
            return (r.snapshot.tokens.map { "\($0.id)/\($0.text)/\($0.state)" }, allEvents)
        }
        let a = run()
        let b = run()
        XCTAssertEqual(a.0, b.0)
        XCTAssertEqual(a.1, b.1)
    }
}
