@testable import TranscriptFX
import XCTest

/// #5141 — when a tier-2 commit lands, the changed words must morph
/// **sequentially left-to-right** (a brief per-word stagger) instead of all on
/// the same frame. The choreography is a per-token animation delay scaled by the
/// token's left-to-right ordinal among the commit's non-provisional words. These
/// tests pin the two pure pieces that produce it: `TranscriptTheme.revisionDelay`
/// (the ordinal → delay curve, incl. the cap) and `TranscriptView.revisionOrder`
/// (the snapshot → per-token ordinal map). The #5125 gate — that the morph fires
/// only for non-provisional tokens — is unchanged and covered in ReconcilerTests.
final class StaggerTests: XCTestCase {
    // MARK: revisionDelay curve

    /// Word 0 fires immediately; each later word is offset by `revisionStagger`,
    /// so a commit's changed words start one after another (the core requirement).
    func testDelayIncreasesLeftToRight() {
        var theme = TranscriptTheme()
        theme.revisionStagger = 0.045
        theme.maxRevisionStagger = 10 // high cap so the ramp isn't clamped here

        let delays = (0 ..< 5).map { theme.revisionDelay(forIndex: $0) }

        XCTAssertEqual(delays[0], 0, "the first changed word morphs without delay")
        for i in 1 ..< delays.count {
            XCTAssertGreaterThan(
                delays[i], delays[i - 1],
                "word \(i) must start strictly later than word \(i - 1) — left-to-right ripple"
            )
        }
        XCTAssertEqual(delays[3], 3 * 0.045, accuracy: 1e-9, "delay scales linearly with ordinal")
    }

    /// A long paragraph must not take seconds to ripple through: past the cap,
    /// every further word starts together at `maxRevisionStagger`.
    func testStaggerIsCappedForLongRuns() {
        var theme = TranscriptTheme()
        theme.revisionStagger = 0.05
        theme.maxRevisionStagger = 0.6 // cap reached at ordinal 12

        XCTAssertEqual(theme.revisionDelay(forIndex: 12), 0.6, accuracy: 1e-9)
        XCTAssertEqual(theme.revisionDelay(forIndex: 50), 0.6, accuracy: 1e-9, "clamped, not 2.5s")
        XCTAssertEqual(theme.revisionDelay(forIndex: 500), 0.6, accuracy: 1e-9, "still clamped")
        XCTAssertLessThanOrEqual(
            theme.revisionDelay(forIndex: .max), theme.maxRevisionStagger,
            "no ordinal may ever exceed the cap"
        )
    }

    /// Disabling the stagger (or a non-positive ordinal) restores the
    /// pre-#5141 all-at-once behavior — every word delay collapses to 0.
    func testZeroStaggerMorphsAllAtOnce() {
        var theme = TranscriptTheme()
        theme.revisionStagger = 0
        for i in 0 ..< 5 {
            XCTAssertEqual(theme.revisionDelay(forIndex: i), 0, "stagger off → no delay for word \(i)")
        }

        var staggered = TranscriptTheme()
        staggered.revisionStagger = 0.045
        XCTAssertEqual(staggered.revisionDelay(forIndex: 0), 0)
        XCTAssertEqual(staggered.revisionDelay(forIndex: -3), 0, "a negative ordinal carries no delay")
    }

    /// The default theme must actually stagger (regression guard: a 0 default
    /// would silently reintroduce the all-at-once flash #5141 set out to fix).
    func testDefaultThemeStaggers() {
        let theme = TranscriptTheme.default
        XCTAssertGreaterThan(theme.revisionStagger, 0, "the shipped default must stagger the morph")
        XCTAssertGreaterThan(
            theme.revisionDelay(forIndex: 2), theme.revisionDelay(forIndex: 1),
            "the shipped default produces a left-to-right ripple out of the box"
        )
        // "followable but not slow": a single word's offset stays well under a
        // quarter second, and the whole ripple is bounded.
        XCTAssertLessThanOrEqual(theme.revisionStagger, 0.08)
        XCTAssertLessThanOrEqual(theme.maxRevisionStagger, 1.0)
    }

    // MARK: revisionRunIndex — the reconciler stamps the changed run

    /// The tokens a tier-2 commit corrected (those that emit a `.revise`) carry
    /// `revisionRunIndex` 0,1,2… in reading order; their `revision` bumped so they
    /// morph. The whole point of the feature, asserted on real reconciler output.
    func testCommitStampsRunIndexLeftToRight() {
        let r = TranscriptReconciler(configuration: .twoTier)
        r.apply(TranscriptUpdate(text: "the meeting iz at too thirty"))
        // The tier-2 commit: this is the morph (#5125 gate already covered).
        let events = r.apply(TranscriptUpdate(text: "The meeting is at 2:30", tier: .refined, isFinal: false))

        let revisedIDs = Set(events.compactMap { event -> String? in
            if case let .revise(id, _, _) = event { return id }
            return nil
        })
        XCTAssertFalse(revisedIDs.isEmpty, "the refined commit changed at least one word to stagger")

        // In flat reading order, the changed run's tokens are numbered 0,1,2,…
        var expected = 0
        for token in r.snapshot.tokens where revisedIDs.contains(token.id) {
            XCTAssertEqual(token.revisionRunIndex, expected, "changed token '\(token.text)' carries its reading-order index")
            XCTAssertGreaterThan(token.revision, 0, "a changed token's revision bumped (it will morph)")
            expected += 1
        }

        // The delays those indices produce ripple left-to-right — non-decreasing,
        // and the last changed word strictly later than the first. (Would FAIL if
        // revisionDelay were constant, so this is not vacuous.)
        let theme = TranscriptTheme.default
        let runDelays = r.snapshot.tokens
            .filter { revisedIDs.contains($0.id) }
            .map { theme.revisionDelay(forIndex: $0.revisionRunIndex) }
        for i in 1 ..< runDelays.count {
            XCTAssertGreaterThanOrEqual(runDelays[i], runDelays[i - 1], "delay must not decrease across the run")
        }
        if runDelays.count > 1 {
            XCTAssertGreaterThan(runDelays.last ?? 0, runDelays.first ?? 0, "not all changed words morph on one frame")
        }
    }

    /// THE #4 REGRESSION GUARD (reviewer must-fix): a commit landing AFTER a long
    /// settled prefix must still stagger from index 0. An implementation that
    /// numbered among *all* non-provisional tokens would give the first changed
    /// word an index ≥ prefix length → instantly clamped to the cap → every word
    /// morphs simultaneously again. The reconciler numbers only the changed run,
    /// so its first word is always index 0 regardless of how much precedes it.
    func testRunIndexStartsFromZeroAfterALongSettledPrefix() {
        let r = TranscriptReconciler(configuration: .twoTier)
        // Commit a long first utterance so the paragraph carries many finalized
        // tokens before the next commit's changed run.
        let prefix = (1 ... 20).map { "w\($0)" }.joined(separator: " ")
        r.apply(TranscriptUpdate(text: prefix, isFinal: true))
        r.apply(TranscriptUpdate(text: prefix, tier: .refined, isFinal: true))

        // A SECOND utterance: preview, then a tier-2 correction on three words.
        r.apply(TranscriptUpdate(text: "teh quikc broun"))
        let events = r.apply(TranscriptUpdate(text: "the quick brown", tier: .refined, isFinal: false))
        let revisedIDs = Set(events.compactMap { event -> String? in
            if case let .revise(id, _, _) = event { return id }
            return nil
        })
        XCTAssertFalse(revisedIDs.isEmpty, "the second commit changed words")

        let runIndices = r.snapshot.tokens
            .filter { revisedIDs.contains($0.id) }
            .map(\.revisionRunIndex)
        XCTAssertEqual(runIndices.min(), 0, "the run's first word is index 0 regardless of prefix length")
        XCTAssertEqual(runIndices.sorted(), Array(0 ..< runIndices.count), "run indices are dense from 0")

        // The long finalized prefix is NOT renumbered — it stays at 0 and, having
        // not bumped its revision, never morphs.
        let prefixTokens = r.snapshot.tokens.prefix(20)
        XCTAssertTrue(prefixTokens.allSatisfy { $0.revisionRunIndex == 0 }, "settled prefix is not part of the run")

        // The regression's tell was a first-word delay pinned at the cap.
        let theme = TranscriptTheme.default
        XCTAssertEqual(
            theme.revisionDelay(forIndex: runIndices.min() ?? -1), 0, accuracy: 1e-9,
            "first changed word must morph immediately, not at maxRevisionStagger"
        )
    }

    /// The run index is per-commit: a later commit renumbers from 0 and the
    /// previous commit's settled words are cleared back to 0 (so an old run can
    /// never re-stagger and a stale offset can't leak into a future morph).
    func testRunIndexIsClearedBetweenCommits() {
        let r = TranscriptReconciler(configuration: .twoTier)
        // Commit 1 (final) over four words.
        r.apply(TranscriptUpdate(text: "alpha beta gamma delta"))
        r.apply(TranscriptUpdate(text: "ALPHA BETA GAMMA DELTA", tier: .refined, isFinal: true))
        let firstRunMax = r.snapshot.tokens.map(\.revisionRunIndex).max() ?? 0
        XCTAssertGreaterThan(firstRunMax, 0, "commit 1 numbered a multi-word run")

        // Commit 2 (final) on a fresh utterance of two words.
        r.apply(TranscriptUpdate(text: "epsilon zeta"))
        r.apply(TranscriptUpdate(text: "EPSILON ZETA", tier: .refined, isFinal: true))

        // Commit 1's words are back to index 0 (cleared); commit 2's words are the
        // only ones carrying a fresh 0,1 run.
        let firstFour = Array(r.snapshot.tokens.prefix(4))
        XCTAssertTrue(firstFour.allSatisfy { $0.revisionRunIndex == 0 }, "prior commit's run indices are cleared")
        let lastTwo = Array(r.snapshot.tokens.suffix(2))
        XCTAssertEqual(lastTwo.map(\.revisionRunIndex), [0, 1], "the latest commit renumbers from 0")
    }

    /// Preview-only ticks never stamp a run (no `.revise`, no morph), so every
    /// token's `revisionRunIndex` stays 0 — the #5125 gate, re-asserted via the
    /// new field so a future change can't quietly start staggering preview text.
    func testPreviewNeverStampsARun() {
        let r = TranscriptReconciler(configuration: .twoTier)
        for tick in ["the", "the meetingg", "the meeting iz", "the meeting is at two"] {
            r.apply(TranscriptUpdate(text: tick))
        }
        XCTAssertTrue(
            r.snapshot.tokens.allSatisfy { $0.revisionRunIndex == 0 && $0.revision == 0 && $0.state == .provisional },
            "no preview tick may stamp a run index or bump a revision before a commit"
        )
    }

    /// A split's leading fragment and a merge's surviving token morph in place
    /// (their text/revision change) but emit `.split`/`.merge` instead of
    /// `.revise`, so they must still be folded into the staggered run — otherwise
    /// they'd morph out of step at delay 0 (reviewer finding A).
    func testSplitAndMergeTokensJoinTheRun() {
        // Split: "gonna" → "going to". The leading fragment keeps identity + morphs.
        let split = TranscriptReconciler()
        split.apply(TranscriptUpdate(words: [TranscriptWord(text: "gonna", start: 0, end: 0.5, confidence: 0.5)]))
        let splitID = split.snapshot.tokens[0].id
        split.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "going", start: 0, end: 0.25, confidence: 0.97),
            TranscriptWord(text: "to", start: 0.25, end: 0.5, confidence: 0.97),
        ], tier: .refined))
        let leading = split.snapshot.tokens.first { $0.id == splitID }
        XCTAssertEqual(leading?.revisionRunIndex, 0, "split's morphing fragment is the run's first word")
        XCTAssertGreaterThan(leading?.revision ?? 0, 0, "the split fragment bumped its revision (it morphs)")

        // Merge: "two" "thirty" → "2:30". The surviving token keeps identity + morphs.
        let merge = TranscriptReconciler()
        merge.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "two", start: 1.4, end: 1.8),
            TranscriptWord(text: "thirty", start: 1.8, end: 2.2),
        ]))
        let survivorID = merge.snapshot.tokens[0].id
        merge.apply(TranscriptUpdate(words: [
            TranscriptWord(text: "2:30", start: 1.4, end: 2.2, confidence: 0.97),
        ], tier: .refined))
        let survivor = merge.snapshot.tokens.first { $0.id == survivorID }
        XCTAssertEqual(survivor?.revisionRunIndex, 0, "merge's surviving token is in the run")
        XCTAssertGreaterThan(survivor?.revision ?? 0, 0, "the merged token bumped its revision (it morphs)")
    }

    /// A zero-event apply (e.g. a two-tier app's trailing preview re-flow in the
    /// SAME sync as a commit) must NOT clear the run the preceding refined commit
    /// just stamped. SwiftUI coalesces both `@Published` snapshot writes into one
    /// render, so a clear-on-no-op would leave the view with an all-zero run →
    /// every word morphs on one frame (offrecord #5141 regression). The run is
    /// preserved across the no-op; the NEXT real commit still clears it.
    func testZeroEventApplyDoesNotClearTheStampedRun() {
        let r = TranscriptReconciler(configuration: .twoTier)
        // Rough preview, then a refined commit that morphs two words (stamps run).
        r.apply(TranscriptUpdate(text: "helo wrld going on"))
        let commit = r.apply(TranscriptUpdate(text: "hello world going on", tier: .refined, isFinal: false))
        let revisedIDs = Set(commit.compactMap { event -> String? in
            if case let .revise(id, _, _) = event { return id }
            return nil
        })
        XCTAssertEqual(revisedIDs.count, 2, "the commit morphed two words")
        let runBefore = r.snapshot.tokens.filter { revisedIDs.contains($0.id) }.map(\.revisionRunIndex)
        XCTAssertEqual(runBefore, [0, 1], "the commit stamped a left-to-right run")

        // A trailing preview re-flow of the SAME (already-correct) text → zero
        // events (committed tokens are .revised so preview skips them; tail text
        // unchanged). This must NOT wipe the run.
        let trailing = r.apply(TranscriptUpdate(text: "hello world going on"))
        XCTAssertTrue(trailing.isEmpty, "the trailing preview re-flow is a no-op")
        let runAfter = r.snapshot.tokens.filter { revisedIDs.contains($0.id) }.map(\.revisionRunIndex)
        XCTAssertEqual(
            runAfter, [0, 1],
            "a zero-event apply must preserve the stamped run (else the #5141 stagger dies under coalescing)"
        )

        // The next REAL commit still clears the prior run and stamps its own.
        r.apply(TranscriptUpdate(text: "hello world going ON", tier: .refined, isFinal: false))
        let firstTwo = Array(r.snapshot.tokens.prefix(2))
        XCTAssertTrue(firstTwo.allSatisfy { $0.revisionRunIndex == 0 }, "the prior run is cleared by the next commit")
    }
}
