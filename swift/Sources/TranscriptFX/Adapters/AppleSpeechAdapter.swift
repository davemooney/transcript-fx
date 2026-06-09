import Foundation

/// Pure, testable Apple-segment → `TranscriptUpdate` mapping.
public func appleSegmentsToUpdate(
    _ segments: [(text: String, timestamp: Double, duration: Double, confidence: Float)],
    tier: SourceTier = .preview,
    isFinal: Bool,
    utteranceID: String? = nil,
    speaker: SpeakerID? = nil
) -> TranscriptUpdate {
    let words = segments.map {
        TranscriptWord(
            text: $0.text,
            start: $0.timestamp,
            end: $0.timestamp + $0.duration,
            confidence: $0.confidence > 0 ? Double($0.confidence) : nil
        )
    }
    return TranscriptUpdate(words: words, tier: tier, isFinal: isFinal, utteranceID: utteranceID, speaker: speaker)
}

#if canImport(Speech)
import Speech

/// Drop-in: `SFSpeechRecognitionResult` → `TranscriptUpdate`.
///
/// Apple SpeechAnalyzer / SpeechTranscriber (iOS/macOS 26+) results map the
/// same way — its volatile/finalized results carry segments with
/// `audioTimeRange`, which become the same `start`/`end` here.
@available(iOS 13.0, macOS 10.15, *)
public func speechResultToUpdate(
    _ result: SFSpeechRecognitionResult,
    tier: SourceTier = .preview,
    utteranceID: String? = nil,
    speaker: SpeakerID? = nil
) -> TranscriptUpdate {
    let segments = result.bestTranscription.segments.map {
        (text: $0.substring, timestamp: $0.timestamp, duration: $0.duration, confidence: $0.confidence)
    }
    return appleSegmentsToUpdate(segments, tier: tier, isFinal: result.isFinal, utteranceID: utteranceID, speaker: speaker)
}
#endif
