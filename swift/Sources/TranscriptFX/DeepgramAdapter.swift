import Foundation

// Deepgram streaming JSON (subset). (Spec §2)
public struct DeepgramWord: Decodable, Sendable {
    public let word: String
    public let punctuatedWord: String?
    public let confidence: Double
    enum CodingKeys: String, CodingKey {
        case word, confidence
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

/// Mirrors the TS `createDeepgramConsumer`: reconciles interim results into
/// append/revise/remove events, committing a fresh segment on `is_final`.
@MainActor
public final class DeepgramConsumer {
    private let sink: TranscriptSink
    private var segment = 0
    private var live: [(id: String, text: String)] = []

    public init(sink: TranscriptSink) { self.sink = sink }
    public convenience init(model: TranscriptModel) { self.init(sink: model) }

    public func reset() {
        segment = 0
        live.removeAll()
    }

    public func apply(_ res: DeepgramResult) {
        guard let alt = res.channel?.alternatives.first else { return }
        let words = alt.words

        for i in words.indices {
            let text = words[i].punctuatedWord ?? words[i].word
            if i < live.count {
                if live[i].text != text {
                    sink.revise(live[i].id, text)
                    live[i].text = text
                }
            } else {
                let id = "\(segment)-\(i)"
                sink.append(id, text, confidence: words[i].confidence)
                live.append((id, text))
            }
        }

        if words.count < live.count {
            for i in words.count..<live.count { sink.remove(live[i].id) }
            live.removeLast(live.count - words.count)
        }

        if res.isFinal == true {
            segment += 1
            live.removeAll()
        }
    }

    /// Decode a raw Deepgram `Results` message and apply it.
    public func apply(jsonData: Data) {
        guard let res = try? JSONDecoder().decode(DeepgramResult.self, from: jsonData) else { return }
        apply(res)
    }
}
