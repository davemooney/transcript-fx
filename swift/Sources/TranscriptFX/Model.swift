import Foundation

// MARK: - Canonical input model
//
// The contract between an app and TranscriptFX. The app normalizes whatever its
// ASR emits into `TranscriptUpdate`s; the library owns everything after that:
// token identity, revision semantics, segmentation, and presentation.

public typealias Seconds = Double

/// Which recognition tier produced an update.
/// `preview` is the fast tier-1 stream the user sees instantly;
/// `refined` is the slower, more accurate tier-2 pass that corrects it.
public enum SourceTier: String, Sendable, Codable {
    case preview
    case refined
}

/// Lifecycle of a token.
/// `provisional` — produced by the preview tier, may still change.
/// `revised` — touched by the refined tier, not yet committed.
/// `finalized` — committed; will never change again.
public enum TokenState: String, Sendable, Codable {
    case provisional
    case revised
    case finalized
}

/// Identifies a speaker. Wrap whatever your diarization emits ("0", "alice", …).
public struct SpeakerID: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}

/// One word as the app hands it in. Everything beyond `text` is optional and
/// unlocks behavior: times → timestamp alignment, confidence → ink-settle,
/// speaker → speaker-aware paragraphs.
public struct TranscriptWord: Equatable, Sendable {
    public var text: String
    public var start: Seconds?
    public var end: Seconds?
    public var confidence: Double?
    public var speaker: SpeakerID?

    public init(
        text: String,
        start: Seconds? = nil,
        end: Seconds? = nil,
        confidence: Double? = nil,
        speaker: SpeakerID? = nil
    ) {
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
        self.speaker = speaker
    }
}

/// The single envelope an app feeds the library — one ASR result, normalized.
///
/// `utteranceID` is the app's (or the ASR's) segment identity. When provided,
/// preview updates with the same ID refine the same utterance, and refined
/// updates target that utterance directly. Without it, the reconciler targets
/// by time overlap, falling back to the most recent open utterance.
public struct TranscriptUpdate: Equatable, Sendable {
    public var words: [TranscriptWord]
    public var tier: SourceTier
    public var isFinal: Bool
    public var utteranceID: String?
    /// Utterance-level speaker, applied to words that have no word-level speaker.
    public var speaker: SpeakerID?

    public init(
        words: [TranscriptWord],
        tier: SourceTier = .preview,
        isFinal: Bool = false,
        utteranceID: String? = nil,
        speaker: SpeakerID? = nil
    ) {
        self.words = words
        self.tier = tier
        self.isFinal = isFinal
        self.utteranceID = utteranceID
        self.speaker = speaker
    }

    /// Plain-string convenience for sources without word-level output; the
    /// library tokenizes on whitespace.
    public init(
        text: String,
        tier: SourceTier = .preview,
        isFinal: Bool = false,
        utteranceID: String? = nil,
        speaker: SpeakerID? = nil
    ) {
        let words = text
            .split(whereSeparator: { $0.isWhitespace })
            .map { TranscriptWord(text: String($0)) }
        self.init(words: words, tier: tier, isFinal: isFinal, utteranceID: utteranceID, speaker: speaker)
    }
}

/// Adapter seam: conform your raw ASR chunk type to feed it straight into a
/// `TranscriptSession` without an intermediate mapping call at every site.
public protocol TranscriptUpdateConvertible {
    var transcriptUpdate: TranscriptUpdate { get }
}

extension TranscriptUpdate: TranscriptUpdateConvertible {
    public var transcriptUpdate: TranscriptUpdate { self }
}

// MARK: - Canonical output model

/// One presented token. `id` is stable across revisions — that stability is
/// what lets corrections animate in place instead of redrawing.
/// `revision` increments every time the text changes; views key flash/morph
/// animations off it.
public struct TranscriptToken: Identifiable, Equatable, Sendable {
    public let id: String
    public var text: String
    public var state: TokenState
    public var tier: SourceTier
    public var confidence: Double?
    public var start: Seconds?
    public var end: Seconds?
    public var speaker: SpeakerID?
    public var revision: Int

    public init(
        id: String,
        text: String,
        state: TokenState = .provisional,
        tier: SourceTier = .preview,
        confidence: Double? = nil,
        start: Seconds? = nil,
        end: Seconds? = nil,
        speaker: SpeakerID? = nil,
        revision: Int = 0
    ) {
        self.id = id
        self.text = text
        self.state = state
        self.tier = tier
        self.confidence = confidence
        self.start = start
        self.end = end
        self.speaker = speaker
        self.revision = revision
    }

    public var isFinalized: Bool { state == .finalized }
}

/// A run of tokens ending at a sentence boundary. ID derives from the first
/// token, so a settled sentence keeps its identity as later text streams in.
public struct TranscriptSentence: Identifiable, Equatable, Sendable {
    public let id: String
    public var tokens: [TranscriptToken]

    public init(id: String, tokens: [TranscriptToken]) {
        self.id = id
        self.tokens = tokens
    }

    /// True when every token in the sentence is finalized — the cue for
    /// sentence-level settle styling.
    public var isSettled: Bool { tokens.allSatisfy(\.isFinalized) }
}

/// A run of sentences by one speaker, broken on speaker change or long pause.
public struct TranscriptParagraph: Identifiable, Equatable, Sendable {
    public let id: String
    public var speaker: SpeakerID?
    public var sentences: [TranscriptSentence]

    public init(id: String, speaker: SpeakerID? = nil, sentences: [TranscriptSentence]) {
        self.id = id
        self.speaker = speaker
        self.sentences = sentences
    }

    public var tokens: [TranscriptToken] { sentences.flatMap(\.tokens) }
    public var isSettled: Bool { sentences.allSatisfy(\.isSettled) }
}

/// What the library hands the view layer after each update: the flat token
/// timeline (the animation substrate) plus its sentence/paragraph grouping.
public struct TranscriptSnapshot: Equatable, Sendable {
    public var tokens: [TranscriptToken]
    public var paragraphs: [TranscriptParagraph]
    /// True while an utterance is still streaming (drives the live caret).
    public var isLive: Bool

    public init(tokens: [TranscriptToken] = [], paragraphs: [TranscriptParagraph] = [], isLive: Bool = false) {
        self.tokens = tokens
        self.paragraphs = paragraphs
        self.isLive = isLive
    }

    public static let empty = TranscriptSnapshot()

    /// The transcript as plain text (finalized and pending alike).
    public var text: String {
        paragraphs.map { p in p.tokens.map(\.text).joined(separator: " ") }.joined(separator: "\n\n")
    }
}
