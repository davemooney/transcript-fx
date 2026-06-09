import Foundation

/// Explicit, semantic description of what an update did to the transcript.
/// The reconciler returns these from every `apply` — apps can drive haptics,
/// analytics, accessibility announcements, or custom rendering off them
/// without diffing snapshots themselves.
public enum RevisionEvent: Equatable, Sendable {
    /// A new token appeared at `index` in the flat timeline.
    case insert(id: String, index: Int)
    /// A token was removed.
    case remove(id: String)
    /// A token's text changed in place — identity kept, so it animates as a morph.
    case revise(id: String, oldText: String, newText: String)
    /// A token was swapped for a different one (identity could not be kept).
    case replace(removedID: String, insertedID: String)
    /// One token became several (e.g. "gonna" → "going to"). The first new
    /// ID is the original token's, so the leading fragment morphs in place.
    case split(id: String, into: [String])
    /// Several tokens collapsed into one (e.g. "two" "thirty" → "2:30").
    /// The surviving ID is the first of the merged tokens.
    case merge(ids: [String], into: String)
    /// These tokens were committed and will never change again.
    case finalize(ids: [String])
    /// A token's speaker attribution changed.
    case speakerChange(id: String, from: SpeakerID?, to: SpeakerID?)
    /// A sentence boundary now exists after this token.
    case sentenceBreak(afterID: String)
    /// A paragraph boundary now exists after this token.
    case paragraphBreak(afterID: String)
}

/// How refined words are matched onto existing tokens.
public enum AlignmentPolicy: Sendable {
    /// Timestamp overlap when both sides are fully timed, with text matching
    /// inside ambiguous overlap clusters. Falls back to text alignment when
    /// timestamps are missing. The right default for almost everyone.
    case hybrid
    /// Timestamp overlap when fully timed (positional pairing inside
    /// clusters); positional alignment otherwise.
    case timestampFirst
    /// Always align by text similarity, ignoring timestamps.
    case textFirst
}

/// When tokens become `finalized`.
public enum FinalizationPolicy: Sendable {
    /// Any `isFinal` update finalizes its utterance. Right for single-tier apps.
    case onAnyFinal
    /// Only a refined `isFinal` update (or an explicit `finalizeAll()`)
    /// finalizes. Right for two-tier apps, where the preview tier's "final"
    /// just means "utterance complete, refinement still coming".
    case onRefinedFinal
}

/// How sentence and paragraph boundaries are derived from the token timeline.
public struct SegmentationPolicy: Sendable {
    /// A token ending in one of these closes a sentence.
    public var sentenceTerminators: Set<Character>
    /// A silence gap of at least this many seconds between consecutive timed
    /// tokens starts a new paragraph.
    public var paragraphPause: Seconds
    /// Whether a speaker change starts a new paragraph.
    public var paragraphOnSpeakerChange: Bool
    /// Whether the end of an utterance closes a sentence even without
    /// terminal punctuation.
    public var sentenceOnUtteranceEnd: Bool

    public init(
        sentenceTerminators: Set<Character> = [".", "!", "?", "…"],
        paragraphPause: Seconds = 2.0,
        paragraphOnSpeakerChange: Bool = true,
        sentenceOnUtteranceEnd: Bool = true
    ) {
        self.sentenceTerminators = sentenceTerminators
        self.paragraphPause = paragraphPause
        self.paragraphOnSpeakerChange = paragraphOnSpeakerChange
        self.sentenceOnUtteranceEnd = sentenceOnUtteranceEnd
    }
}

/// Everything tunable about reconciliation, with defaults that fit a
/// two-tier streaming app.
public struct ReconcilerConfiguration: Sendable {
    public var alignment: AlignmentPolicy
    public var finalization: FinalizationPolicy
    public var segmentation: SegmentationPolicy

    public init(
        alignment: AlignmentPolicy = .hybrid,
        finalization: FinalizationPolicy = .onAnyFinal,
        segmentation: SegmentationPolicy = SegmentationPolicy()
    ) {
        self.alignment = alignment
        self.finalization = finalization
        self.segmentation = segmentation
    }

    /// Preset for apps with a fast preview tier and a slower refined tier:
    /// preview finals close the utterance but leave it revisable until the
    /// refined pass lands.
    public static let twoTier = ReconcilerConfiguration(finalization: .onRefinedFinal)
}
