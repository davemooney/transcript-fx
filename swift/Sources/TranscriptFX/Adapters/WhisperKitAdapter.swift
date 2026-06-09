import Foundation

/// Conform WhisperKit's `WordTiming` to this — the property names already
/// match, so it's a one-liner with zero glue:
///
///     import WhisperKit
///     extension WordTiming: WhisperWordTiming {}
///
/// then `session.ingest(whisperKitToUpdate(segment.words ?? [], isFinal: true))`.
public protocol WhisperWordTiming {
    var word: String { get }
    var start: Float { get }
    var end: Float { get }
    var probability: Float { get }
}

/// Drop-in: WhisperKit word timings → `TranscriptUpdate`. WhisperKit is the
/// classic tier-2 refiner, so the tier defaults to `.refined`.
public func whisperKitToUpdate<W: WhisperWordTiming>(
    _ words: [W],
    tier: SourceTier = .refined,
    isFinal: Bool,
    utteranceID: String? = nil,
    speaker: SpeakerID? = nil
) -> TranscriptUpdate {
    let mapped = words.map {
        TranscriptWord(
            text: $0.word.trimmingCharacters(in: .whitespaces), // Whisper tokens carry a leading space
            start: Double($0.start),
            end: Double($0.end),
            confidence: Double($0.probability)
        )
    }
    return TranscriptUpdate(words: mapped, tier: tier, isFinal: isFinal, utteranceID: utteranceID, speaker: speaker)
}
