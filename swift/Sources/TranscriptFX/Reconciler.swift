import Foundation

/// Turns preview and refined `TranscriptUpdate`s into one stable token
/// timeline, emitting explicit `RevisionEvent`s for every change.
///
/// Internally the timeline is a sequence of utterances. Preview updates
/// stream into the open utterance positionally (interim ASR results are
/// prefix-stable). Refined updates are targeted at an utterance — by
/// `utteranceID`, else by time overlap, else the most recent unfinalized
/// one — and aligned onto its tokens timestamps-first (`AlignmentPolicy`),
/// reusing token IDs so corrections animate in place.
///
/// Deterministic: the same sequence of updates always yields the same
/// tokens and events. No clocks, no randomness.
public final class TranscriptReconciler {
    public let configuration: ReconcilerConfiguration
    public private(set) var snapshot: TranscriptSnapshot = .empty

    struct Utterance {
        var externalID: String?
        var tokens: [TranscriptToken]
        /// Preview is still streaming into it.
        var isOpen: Bool
        var isFinalized: Bool
    }

    private var utterances: [Utterance] = []
    private var tokenSeq = 0
    private var knownSentenceBreaks: Set<String> = []
    private var knownParagraphBreaks: Set<String> = []

    public init(configuration: ReconcilerConfiguration = ReconcilerConfiguration()) {
        self.configuration = configuration
    }

    public func reset() {
        utterances = []
        tokenSeq = 0
        knownSentenceBreaks = []
        knownParagraphBreaks = []
        snapshot = .empty
    }

    /// Apply one update and return the semantic changes it caused.
    @discardableResult
    public func apply(_ update: TranscriptUpdate) -> [RevisionEvent] {
        var events: [RevisionEvent] = []
        switch update.tier {
        case .preview: applyPreview(update, events: &events)
        case .refined: applyRefined(update, events: &events)
        }
        rebuild(&events)
        return events
    }

    /// Commit everything; nothing will change after this.
    @discardableResult
    public func finalizeAll() -> [RevisionEvent] {
        var events: [RevisionEvent] = []
        for i in utterances.indices {
            utterances[i].isOpen = false
            finalize(utteranceAt: i, events: &events)
        }
        rebuild(&events)
        return events
    }

    // MARK: - Preview tier (positional streaming into the open utterance)

    private func applyPreview(_ update: TranscriptUpdate, events: inout [RevisionEvent]) {
        let idx = previewTarget(update)
        let offset = flatOffset(of: idx)
        var u = utterances[idx]
        let words = update.words

        for (i, w) in words.enumerated() {
            if i < u.tokens.count {
                // A token the refined tier already touched outranks preview text.
                guard u.tokens[i].state == .provisional else { continue }
                applyWord(w, to: &u.tokens[i], updateSpeaker: update.speaker, events: &events,
                          tier: .preview, state: .provisional)
            } else {
                let t = makeToken(w, tier: .preview, state: .provisional, updateSpeaker: update.speaker)
                events.append(.insert(id: t.id, index: offset + u.tokens.count))
                u.tokens.append(t)
            }
        }
        if words.count < u.tokens.count {
            let trailing = u.tokens[words.count...]
            for t in trailing where t.state != .finalized {
                events.append(.remove(id: t.id))
            }
            u.tokens = Array(u.tokens[..<words.count]) + trailing.filter { $0.state == .finalized }
        }
        utterances[idx] = u

        if update.isFinal {
            utterances[idx].isOpen = false
            if configuration.finalization == .onAnyFinal {
                finalize(utteranceAt: idx, events: &events)
            }
        }
    }

    private func previewTarget(_ update: TranscriptUpdate) -> Int {
        if let ext = update.utteranceID {
            if let idx = utterances.lastIndex(where: { $0.externalID == ext }), !utterances[idx].isFinalized {
                return idx
            }
            utterances.append(Utterance(externalID: ext, tokens: [], isOpen: true, isFinalized: false))
            return utterances.count - 1
        }
        if let last = utterances.indices.last, utterances[last].isOpen {
            return last
        }
        utterances.append(Utterance(externalID: nil, tokens: [], isOpen: true, isFinalized: false))
        return utterances.count - 1
    }

    // MARK: - Refined tier (targeted, aligned correction)

    private func applyRefined(_ update: TranscriptUpdate, events: inout [RevisionEvent]) {
        for (idx, words) in refinedTargets(update) {
            if !words.isEmpty {
                align(words, ontoUtteranceAt: idx, updateSpeaker: update.speaker,
                      authoritative: update.isFinal, events: &events)
            }
            if update.isFinal {
                utterances[idx].isOpen = false
                finalize(utteranceAt: idx, events: &events)
            }
        }
    }

    /// Which utterance(s) a refined update corrects. A timed update spanning
    /// several utterances is partitioned between them, so a tier-2 pass over
    /// a long audio window lands on the right tier-1 segments.
    private func refinedTargets(_ update: TranscriptUpdate) -> [(index: Int, words: [TranscriptWord])] {
        let words = update.words
        if let ext = update.utteranceID,
           let idx = utterances.lastIndex(where: { $0.externalID == ext && !$0.isFinalized }) {
            return [(idx, words)]
        }

        let candidates = utterances.indices.filter { !utterances[$0].isFinalized }
        let fullyTimed = !words.isEmpty && words.allSatisfy { $0.start != nil && $0.end != nil }
        if fullyTimed {
            let ranged: [(index: Int, range: ClosedRange<Seconds>)] = candidates.compactMap { i in
                let starts = utterances[i].tokens.compactMap(\.start)
                let ends = utterances[i].tokens.compactMap(\.end)
                guard let lo = starts.min(), let hi = ends.max(), lo <= hi else { return nil }
                return (i, lo...hi)
            }
            if !ranged.isEmpty {
                var groups: [(index: Int, words: [TranscriptWord])] = []
                for w in words {
                    let best = ranged.min { lhs, rhs in
                        let a = utteranceAffinity(w, lhs.range), b = utteranceAffinity(w, rhs.range)
                        return a == b ? lhs.index < rhs.index : a < b
                    }!
                    if let last = groups.indices.last, groups[last].index == best.index {
                        groups[last].words.append(w)
                    } else {
                        groups.append((best.index, [w]))
                    }
                }
                return groups
            }
        }
        if let last = candidates.last {
            return [(last, words)]
        }
        // Refined-only stream with no prior preview: open a fresh utterance.
        utterances.append(Utterance(externalID: update.utteranceID, tokens: [], isOpen: false, isFinalized: false))
        return [(utterances.count - 1, words)]
    }

    /// Lower is better: negative overlap when the word intersects the
    /// utterance, positive gap distance when it does not.
    private func utteranceAffinity(_ w: TranscriptWord, _ range: ClosedRange<Seconds>) -> Seconds {
        let overlapAmount = min(w.end!, range.upperBound) - max(w.start!, range.lowerBound)
        return overlapAmount > 0 ? -overlapAmount : max(range.lowerBound - w.end!, w.start! - range.upperBound)
    }

    private func align(
        _ words: [TranscriptWord],
        ontoUtteranceAt idx: Int,
        updateSpeaker: SpeakerID?,
        authoritative: Bool,
        events: inout [RevisionEvent]
    ) {
        let tokens = utterances[idx].tokens
        let wordsTimed = words.allSatisfy { $0.start != nil && $0.end != nil }
        let tokensTimed = !tokens.isEmpty && tokens.allSatisfy { $0.start != nil && $0.end != nil }

        var out: AlignOutcome
        switch configuration.alignment {
        case .hybrid where wordsTimed && tokensTimed,
             .timestampFirst where wordsTimed && tokensTimed:
            out = alignTimed(words, tokens, updateSpeaker: updateSpeaker,
                             textPairing: configuration.alignment == .hybrid,
                             authoritative: authoritative)
        case .timestampFirst:
            out = alignPositional(words, ArraySlice(tokens), updateSpeaker: updateSpeaker)
        case .hybrid, .textFirst:
            out = alignByText(words, ArraySlice(tokens), updateSpeaker: updateSpeaker)
        }

        // Localize insert indices into the flat timeline.
        let offset = flatOffset(of: idx)
        out.events = out.events.map { e in
            if case let .insert(id, local) = e { return .insert(id: id, index: offset + local) }
            return e
        }
        utterances[idx].tokens = out.rebuilt
        events += out.events
    }

    // MARK: - Alignment cores

    private struct AlignOutcome {
        var rebuilt: [TranscriptToken] = []
        var events: [RevisionEvent] = []
    }

    /// Timestamp alignment: group words and tokens into maximal time-overlap
    /// clusters, then resolve each cluster — 1:1 revise, 1:n merge, m:1 split,
    /// m:n paired by text (hybrid) or position.
    ///
    /// An `authoritative` (final) update replaces the whole utterance, so
    /// unmatched tokens are removed wherever they sit. A non-final update is
    /// a partial overlay: tokens outside its time span are left untouched.
    private func alignTimed(
        _ words: [TranscriptWord],
        _ tokens: [TranscriptToken],
        updateSpeaker: SpeakerID?,
        textPairing: Bool,
        authoritative: Bool
    ) -> AlignOutcome {
        var out = AlignOutcome()
        let spanStart = words.compactMap(\.start).min() ?? 0
        let spanEnd = words.compactMap(\.end).max() ?? 0

        for cluster in timeClusters(words: words, tokens: tokens) {
            let ws = cluster.words.map { words[$0] }
            let ts = cluster.tokens.map { tokens[$0] }
            switch (ws.count, ts.count) {
            case (0, _):
                for t in ts {
                    let covered = authoritative || (t.end! > spanStart && t.start! < spanEnd)
                    if covered {
                        out.events.append(.remove(id: t.id))
                    } else {
                        out.rebuilt.append(t)
                    }
                }
            case (_, 0):
                for w in ws {
                    let t = makeToken(w, tier: .refined, state: .revised, updateSpeaker: updateSpeaker)
                    out.events.append(.insert(id: t.id, index: out.rebuilt.count))
                    out.rebuilt.append(t)
                }
            case (1, 1):
                var t = ts[0]
                applyWord(ws[0], to: &t, updateSpeaker: updateSpeaker, events: &out.events)
                out.rebuilt.append(t)
            case (1, _):
                // n tokens became one word.
                var t = ts[0]
                setWord(ws[0], on: &t, updateSpeaker: updateSpeaker, events: &out.events)
                out.events.append(.merge(ids: ts.map(\.id), into: t.id))
                out.rebuilt.append(t)
            case (_, 1):
                // One token became m words; the first keeps the identity.
                var first = ts[0]
                setWord(ws[0], on: &first, updateSpeaker: updateSpeaker, events: &out.events)
                var ids = [first.id]
                out.rebuilt.append(first)
                for w in ws.dropFirst() {
                    let t = makeToken(w, tier: .refined, state: .revised, updateSpeaker: updateSpeaker)
                    ids.append(t.id)
                    out.rebuilt.append(t)
                }
                out.events.append(.split(id: first.id, into: ids))
            default:
                let inner = textPairing
                    ? alignByText(ws, ArraySlice(ts), updateSpeaker: updateSpeaker)
                    : alignPositional(ws, ArraySlice(ts), updateSpeaker: updateSpeaker)
                out.events += inner.events.map { e in
                    if case let .insert(id, local) = e { return .insert(id: id, index: out.rebuilt.count + local) }
                    return e
                }
                out.rebuilt += inner.rebuilt
            }
        }
        return out
    }

    /// Text alignment: anchor on the longest common subsequence of normalized
    /// words (IDs kept), then pair the gaps positionally — a gap pair with no
    /// characters in common becomes a `replace`, otherwise a `revise`.
    private func alignByText(
        _ words: [TranscriptWord],
        _ tokens: ArraySlice<TranscriptToken>,
        updateSpeaker: SpeakerID?
    ) -> AlignOutcome {
        var out = AlignOutcome()
        let tokenArr = Array(tokens)
        let anchors = lcsPairs(tokenArr.map { normalizedWord($0.text) }, words.map { normalizedWord($0.text) })

        var ti = 0, wi = 0
        func handleGap(_ tEnd: Int, _ wEnd: Int) {
            let gt = tokenArr[ti..<tEnd]
            let gw = words[wi..<wEnd]
            pairPositionally(Array(gw), gt, updateSpeaker: updateSpeaker, allowReplace: true, into: &out)
        }
        for (pt, pw) in anchors {
            handleGap(pt, pw)
            var t = tokenArr[pt]
            applyWord(words[pw], to: &t, updateSpeaker: updateSpeaker, events: &out.events)
            out.rebuilt.append(t)
            ti = pt + 1
            wi = pw + 1
        }
        handleGap(tokenArr.count, words.count)
        return out
    }

    /// Position alignment: pair by index, extras insert/remove.
    private func alignPositional(
        _ words: [TranscriptWord],
        _ tokens: ArraySlice<TranscriptToken>,
        updateSpeaker: SpeakerID?
    ) -> AlignOutcome {
        var out = AlignOutcome()
        pairPositionally(words, tokens, updateSpeaker: updateSpeaker, allowReplace: false, into: &out)
        return out
    }

    private func pairPositionally(
        _ words: [TranscriptWord],
        _ tokens: ArraySlice<TranscriptToken>,
        updateSpeaker: SpeakerID?,
        allowReplace: Bool,
        into out: inout AlignOutcome
    ) {
        let tokenArr = Array(tokens)
        for k in 0..<max(words.count, tokenArr.count) {
            if k < words.count, k < tokenArr.count {
                let w = words[k]
                var t = tokenArr[k]
                if allowReplace, charLCSLength(normalizedWord(t.text), normalizedWord(w.text)) == 0 {
                    let fresh = makeToken(w, tier: .refined, state: .revised, updateSpeaker: updateSpeaker)
                    out.events.append(.replace(removedID: t.id, insertedID: fresh.id))
                    out.rebuilt.append(fresh)
                } else {
                    applyWord(w, to: &t, updateSpeaker: updateSpeaker, events: &out.events)
                    out.rebuilt.append(t)
                }
            } else if k < words.count {
                let t = makeToken(words[k], tier: .refined, state: .revised, updateSpeaker: updateSpeaker)
                out.events.append(.insert(id: t.id, index: out.rebuilt.count))
                out.rebuilt.append(t)
            } else {
                out.events.append(.remove(id: tokenArr[k].id))
            }
        }
    }

    // MARK: - Token mutation

    private func makeToken(
        _ w: TranscriptWord,
        tier: SourceTier,
        state: TokenState,
        updateSpeaker: SpeakerID?
    ) -> TranscriptToken {
        defer { tokenSeq += 1 }
        return TranscriptToken(
            id: "t\(tokenSeq)",
            text: w.text,
            state: state,
            tier: tier,
            confidence: w.confidence,
            start: w.start,
            end: w.end,
            speaker: w.speaker ?? updateSpeaker
        )
    }

    /// Apply a word onto a token, emitting `revise`/`speakerChange` as needed.
    private func applyWord(
        _ w: TranscriptWord,
        to t: inout TranscriptToken,
        updateSpeaker: SpeakerID?,
        events: inout [RevisionEvent],
        tier: SourceTier = .refined,
        state: TokenState = .revised
    ) {
        if t.text != w.text {
            events.append(.revise(id: t.id, oldText: t.text, newText: w.text))
        }
        setWord(w, on: &t, updateSpeaker: updateSpeaker, events: &events, tier: tier, state: state)
    }

    /// Apply a word's content without a `revise` event (split/merge carry
    /// their own semantic event).
    private func setWord(
        _ w: TranscriptWord,
        on t: inout TranscriptToken,
        updateSpeaker: SpeakerID?,
        events: inout [RevisionEvent],
        tier: SourceTier = .refined,
        state: TokenState = .revised
    ) {
        if t.text != w.text {
            t.text = w.text
            t.revision += 1
        }
        t.tier = tier
        if t.state != .finalized {
            t.state = state
        }
        if let c = w.confidence {
            t.confidence = c
        } else if tier == .refined {
            t.confidence = max(t.confidence ?? 0, 0.95)
        }
        if let s = w.start { t.start = s }
        if let e = w.end { t.end = e }
        if let sp = w.speaker ?? updateSpeaker, sp != t.speaker {
            events.append(.speakerChange(id: t.id, from: t.speaker, to: sp))
            t.speaker = sp
        }
    }

    // MARK: - Finalization, segmentation, snapshot

    private func finalize(utteranceAt idx: Int, events: inout [RevisionEvent]) {
        var ids: [String] = []
        for i in utterances[idx].tokens.indices where utterances[idx].tokens[i].state != .finalized {
            utterances[idx].tokens[i].state = .finalized
            ids.append(utterances[idx].tokens[i].id)
        }
        utterances[idx].isFinalized = true
        if !ids.isEmpty {
            events.append(.finalize(ids: ids))
        }
    }

    private func flatOffset(of utteranceIndex: Int) -> Int {
        utterances[..<utteranceIndex].reduce(0) { $0 + $1.tokens.count }
    }

    /// Recompute segmentation, emit newly created boundary events, refresh
    /// the snapshot.
    private func rebuild(_ events: inout [RevisionEvent]) {
        let seg = segmentTranscript(
            utterances: utterances.map { (tokens: $0.tokens, isClosed: !$0.isOpen) },
            policy: configuration.segmentation
        )
        let flat = utterances.flatMap(\.tokens)
        for t in flat {
            if seg.paragraphBreaks.contains(t.id), !knownParagraphBreaks.contains(t.id) {
                events.append(.paragraphBreak(afterID: t.id))
            }
            if seg.sentenceBreaks.contains(t.id), !knownSentenceBreaks.contains(t.id) {
                events.append(.sentenceBreak(afterID: t.id))
            }
        }
        knownParagraphBreaks = seg.paragraphBreaks
        knownSentenceBreaks = seg.sentenceBreaks
        snapshot = TranscriptSnapshot(
            tokens: flat,
            paragraphs: seg.paragraphs,
            isLive: utterances.last?.isOpen ?? false
        )
    }
}

// MARK: - Pure helpers

/// Maximal clusters of mutually time-overlapping words and tokens, in
/// timeline order. All inputs must carry start/end.
func timeClusters(words: [TranscriptWord], tokens: [TranscriptToken]) -> [(words: [Int], tokens: [Int])] {
    var clusters: [(words: [Int], tokens: [Int])] = []
    var i = 0, j = 0
    let eps = 1e-9
    while i < words.count || j < tokens.count {
        var cluster: (words: [Int], tokens: [Int]) = ([], [])
        var clusterEnd: Seconds
        let wStart = i < words.count ? words[i].start! : .infinity
        let tStart = j < tokens.count ? tokens[j].start! : .infinity
        if wStart <= tStart {
            cluster.words.append(i)
            clusterEnd = words[i].end!
            i += 1
        } else {
            cluster.tokens.append(j)
            clusterEnd = tokens[j].end!
            j += 1
        }
        while true {
            let nw = i < words.count ? words[i].start! : .infinity
            let nt = j < tokens.count ? tokens[j].start! : .infinity
            if nw < clusterEnd - eps, nw <= nt {
                cluster.words.append(i)
                clusterEnd = max(clusterEnd, words[i].end!)
                i += 1
            } else if nt < clusterEnd - eps {
                cluster.tokens.append(j)
                clusterEnd = max(clusterEnd, tokens[j].end!)
                j += 1
            } else {
                break
            }
        }
        clusters.append(cluster)
    }
    return clusters
}

/// Lowercased, outer punctuation stripped — the equality used for text anchoring.
func normalizedWord(_ text: String) -> String {
    text.lowercased().trimmingCharacters(in: .punctuationCharacters)
}

/// Longest-common-subsequence index pairs (deterministic backtrack).
func lcsPairs(_ a: [String], _ b: [String]) -> [(Int, Int)] {
    let n = a.count, m = b.count
    guard n > 0, m > 0 else { return [] }
    var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
    for i in stride(from: n - 1, through: 0, by: -1) {
        for j in stride(from: m - 1, through: 0, by: -1) {
            dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
        }
    }
    var pairs: [(Int, Int)] = []
    var i = 0, j = 0
    while i < n, j < m {
        if a[i] == b[j] {
            pairs.append((i, j))
            i += 1
            j += 1
        } else if dp[i + 1][j] >= dp[i][j + 1] {
            i += 1
        } else {
            j += 1
        }
    }
    return pairs
}

/// Character-level LCS length — zero means "no letters in common", which is
/// when a correction renders as a replace instead of an in-place morph.
func charLCSLength(_ a: String, _ b: String) -> Int {
    let ac = Array(a), bc = Array(b)
    guard !ac.isEmpty, !bc.isEmpty else { return 0 }
    var prev = [Int](repeating: 0, count: bc.count + 1)
    for i in 1...ac.count {
        var curr = [Int](repeating: 0, count: bc.count + 1)
        for j in 1...bc.count {
            curr[j] = ac[i - 1] == bc[j - 1] ? prev[j - 1] + 1 : max(prev[j], curr[j - 1])
        }
        prev = curr
    }
    return prev[bc.count]
}
