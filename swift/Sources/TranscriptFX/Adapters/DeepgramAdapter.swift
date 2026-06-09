import Foundation

// Deepgram streaming JSON (subset).
public struct DeepgramWord: Decodable, Sendable {
    public let word: String
    public let punctuatedWord: String?
    public let confidence: Double
    public let start: Double?
    public let end: Double?
    /// Diarization channel index, when `diarize=true`.
    public let speaker: Int?
    enum CodingKeys: String, CodingKey {
        case word, confidence, start, end, speaker
        case punctuatedWord = "punctuated_word"
    }
}

public struct DeepgramAlternative: Decodable, Sendable {
    public let transcript: String
    public let confidence: Double
    public let words: [DeepgramWord]
}

public struct DeepgramChannel: Decodable, Sendable {
    public let alternatives: [DeepgramAlternative]
}

public struct DeepgramResult: Decodable, Sendable {
    public let channel: DeepgramChannel?
    public let isFinal: Bool?
    enum CodingKeys: String, CodingKey {
        case channel
        case isFinal = "is_final"
    }
}

/// Map a decoded Deepgram streaming result to a `TranscriptUpdate`.
/// Diarized speaker indices become `SpeakerID`s ("0", "1", …).
public func deepgramToUpdate(
    _ result: DeepgramResult,
    tier: SourceTier = .preview,
    utteranceID: String? = nil
) -> TranscriptUpdate {
    let words = (result.channel?.alternatives.first?.words ?? []).map {
        TranscriptWord(
            text: $0.punctuatedWord ?? $0.word,
            start: $0.start,
            end: $0.end,
            confidence: $0.confidence,
            speaker: $0.speaker.map { SpeakerID(String($0)) }
        )
    }
    return TranscriptUpdate(words: words, tier: tier, isFinal: result.isFinal ?? false, utteranceID: utteranceID)
}

/// Decode a raw Deepgram `Results` websocket message and map it.
public func deepgramToUpdate(
    jsonData: Data,
    tier: SourceTier = .preview,
    utteranceID: String? = nil
) -> TranscriptUpdate? {
    guard let result = try? JSONDecoder().decode(DeepgramResult.self, from: jsonData) else { return nil }
    return deepgramToUpdate(result, tier: tier, utteranceID: utteranceID)
}
