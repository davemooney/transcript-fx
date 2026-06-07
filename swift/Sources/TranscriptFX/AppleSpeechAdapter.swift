import Foundation

/// Pure, testable Apple-segment → ASRResult mapping. (SPEC §2)
public func appleSegmentsToASR(
    _ segments: [(text: String, timestamp: Double, duration: Double, confidence: Float)],
    isFinal: Bool
) -> ASRResult {
    let words = segments.map {
        ASRWord(
            text: $0.text,
            start: $0.timestamp,
            end: $0.timestamp + $0.duration,
            confidence: $0.confidence > 0 ? Double($0.confidence) : nil
        )
    }
    return ASRResult(words: words, isFinal: isFinal)
}

#if canImport(Speech)
import Speech

/// Drop-in: `SFSpeechRecognitionResult` → `ASRResult`.
///
/// Apple SpeechAnalyzer / SpeechTranscriber (iOS/macOS 26+) results map the same
/// way — its volatile/finalized results carry segments with `audioTimeRange`,
/// which become the same `start`/`end` here.
@available(iOS 13.0, macOS 10.15, *)
public func speechResultToASR(_ result: SFSpeechRecognitionResult) -> ASRResult {
    let segs = result.bestTranscription.segments.map {
        (text: $0.substring, timestamp: $0.timestamp, duration: $0.duration, confidence: $0.confidence)
    }
    var asr = appleSegmentsToASR(segs, isFinal: result.isFinal)
    asr.transcript = result.bestTranscription.formattedString
    return asr
}
#endif
