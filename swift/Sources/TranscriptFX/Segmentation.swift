import Foundation

struct SegmentedTranscript {
    var paragraphs: [TranscriptParagraph]
    /// Token IDs followed by a sentence boundary (punctuation / utterance end).
    var sentenceBreaks: Set<String>
    /// Token IDs followed by a paragraph boundary (speaker change / long pause).
    var paragraphBreaks: Set<String>
}

/// Derive sentence and paragraph structure from the flat token timeline.
/// Pure and deterministic — boundaries are a function of the tokens and the
/// policy, never of arrival order.
func segmentTranscript(
    utterances: [(tokens: [TranscriptToken], isClosed: Bool)],
    policy: SegmentationPolicy
) -> SegmentedTranscript {
    struct Item {
        var token: TranscriptToken
        var endsClosedUtterance: Bool
    }
    var flat: [Item] = []
    for u in utterances {
        for (i, t) in u.tokens.enumerated() {
            flat.append(Item(token: t, endsClosedUtterance: i == u.tokens.count - 1 && u.isClosed))
        }
    }
    guard !flat.isEmpty else {
        return SegmentedTranscript(paragraphs: [], sentenceBreaks: [], paragraphBreaks: [])
    }

    var paragraphBreaks: Set<String> = []
    for k in 1..<flat.count {
        let prev = flat[k - 1].token
        let cur = flat[k].token
        var breaks = false
        if policy.paragraphOnSpeakerChange, let a = prev.speaker, let b = cur.speaker, a != b {
            breaks = true
        }
        if let e = prev.end, let s = cur.start, s - e >= policy.paragraphPause {
            breaks = true
        }
        if breaks {
            paragraphBreaks.insert(prev.id)
        }
    }

    var sentenceBreaks: Set<String> = []
    for item in flat {
        if let last = item.token.text.last, policy.sentenceTerminators.contains(last) {
            sentenceBreaks.insert(item.token.id)
        } else if policy.sentenceOnUtteranceEnd, item.endsClosedUtterance {
            sentenceBreaks.insert(item.token.id)
        }
    }

    var paragraphs: [TranscriptParagraph] = []
    var sentences: [TranscriptSentence] = []
    var run: [TranscriptToken] = []
    for (k, item) in flat.enumerated() {
        run.append(item.token)
        let id = item.token.id
        let isLast = k == flat.count - 1
        if sentenceBreaks.contains(id) || paragraphBreaks.contains(id) || isLast {
            sentences.append(TranscriptSentence(id: "s-\(run[0].id)", tokens: run))
            run = []
        }
        if paragraphBreaks.contains(id) || isLast {
            let tokens = sentences.flatMap(\.tokens)
            paragraphs.append(TranscriptParagraph(
                id: "p-\(tokens[0].id)",
                speaker: tokens.first(where: { $0.speaker != nil })?.speaker,
                sentences: sentences
            ))
            sentences = []
        }
    }
    return SegmentedTranscript(
        paragraphs: paragraphs,
        sentenceBreaks: sentenceBreaks,
        paragraphBreaks: paragraphBreaks
    )
}
