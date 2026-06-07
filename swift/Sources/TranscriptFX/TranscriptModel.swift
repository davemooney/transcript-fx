import SwiftUI

/// volatile = interim/uncommitted, final = committed. (Spec §1)
public enum TokenState: Sendable { case volatile, final }

/// One transcript token. Identity is stable across revisions. (Spec §1)
public struct Token: Identifiable, Equatable, Sendable {
    public let id: String
    public var text: String
    public var state: TokenState
    public var confidence: Double?
    public var redacted: Bool

    public init(
        id: String,
        text: String,
        state: TokenState = .volatile,
        confidence: Double? = nil,
        redacted: Bool = false
    ) {
        self.id = id
        self.text = text
        self.state = state
        self.confidence = confidence
        self.redacted = redacted
    }

    public var isFinal: Bool { state == .final }
    public var isLowConfidence: Bool { (confidence ?? 1) < 0.6 }
}

/// The event surface a provider adapter (Deepgram / Apple SpeechAnalyzer / …) drives. (Spec §1–2)
@MainActor
public final class TranscriptModel: ObservableObject {
    @Published public private(set) var tokens: [Token] = []

    public init() {}

    public func append(_ id: String, _ text: String, confidence: Double? = nil) {
        tokens.append(Token(id: id, text: text, confidence: confidence))
    }

    public func revise(_ id: String, _ text: String) {
        guard let i = tokens.firstIndex(where: { $0.id == id }) else { return }
        tokens[i].text = text
        tokens[i].confidence = 0.95
    }

    public func redact(_ id: String) {
        guard let i = tokens.firstIndex(where: { $0.id == id }) else { return }
        tokens[i].redacted = true
    }

    public func finalizeAll() {
        for i in tokens.indices { tokens[i].state = .final }
    }

    public func remove(_ id: String) {
        tokens.removeAll { $0.id == id }
    }

    public func clear() { tokens.removeAll() }
}

/// The event surface adapters drive — also lets us unit-test op sequences. (Spec §1)
@MainActor
public protocol TranscriptSink: AnyObject {
    func append(_ id: String, _ text: String, confidence: Double?)
    func revise(_ id: String, _ text: String)
    func remove(_ id: String)
}

extension TranscriptModel: TranscriptSink {}
