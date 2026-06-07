import Foundation

/// Conform WhisperKit's `WordTiming` to this — the property names already match,
/// so it's a one-liner with zero glue:
///
///   import WhisperKit
///   extension WordTiming: WhisperWordTiming {}
///
/// then `reconciler.ingest(whisperKitToASR(segment.words ?? [], isFinal: true), role: .refined)`.
public protocol WhisperWordTiming {
    var word: String { get }
    var start: Float { get }
    var end: Float { get }
    var probability: Float { get }
}

/// Drop-in: WhisperKit word timings → ASRResult. (SPEC §2)
public func whisperKitToASR<W: WhisperWordTiming>(_ words: [W], isFinal: Bool) -> ASRResult {
    let mapped = words.map {
        ASRWord(
            text: $0.word.trimmingCharacters(in: .whitespaces), // Whisper tokens carry a leading space
            start: Double($0.start),
            end: Double($0.end),
            confidence: Double($0.probability)
        )
    }
    return ASRResult(words: mapped, isFinal: isFinal)
}
