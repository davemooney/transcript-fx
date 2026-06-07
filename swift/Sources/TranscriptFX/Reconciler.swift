import Foundation

// The canonical ASR result — the one type any provider/tier maps to. (SPEC §2)
public typealias Seconds = Double

public struct ASRWord: Sendable {
    public var text: String
    public var start: Seconds?
    public var end: Seconds?
    public var confidence: Double?
    public init(text: String, start: Seconds? = nil, end: Seconds? = nil, confidence: Double? = nil) {
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

public struct ASRResult: Sendable {
    public var words: [ASRWord]?
    public var transcript: String?
    public var isFinal: Bool
    public var utteranceId: String?
    public init(words: [ASRWord]? = nil, transcript: String? = nil, isFinal: Bool, utteranceId: String? = nil) {
        self.words = words
        self.transcript = transcript
        self.isFinal = isFinal
        self.utteranceId = utteranceId
    }
}

public enum SourceRole: Sendable { case draft, refined }

public struct ReconToken: Identifiable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var state: TokenState
    public var confidence: Double?
    public var start: Double?
    public var end: Double?
}

func resultWords(_ r: ASRResult) -> [ASRWord] {
    if let w = r.words, !w.isEmpty { return w }
    let t = (r.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return [] }
    return t.split(whereSeparator: { $0.isWhitespace }).map { ASRWord(text: String($0)) }
}

/// Reconciles 1+ ASR sources into a single token timeline. Mirrors the TS
/// `TranscriptReconciler` exactly (verified against shared fixtures). (SPEC §2b)
public final class TranscriptReconciler {
    public private(set) var tokens: [ReconToken] = []
    private var activeStart = 0
    private var seq = 0

    public init() {}

    public func reset() {
        tokens = []
        activeStart = 0
        seq = 0
    }

    public func ingest(_ result: ASRResult, role: SourceRole = .draft) {
        let words = resultWords(result)
        if role == .refined {
            ingestRefined(words, result.isFinal)
        } else {
            ingestDraft(words, result.isFinal)
        }
    }

    private func newId() -> String {
        defer { seq += 1 }
        return "t\(seq)"
    }

    private func makeToken(_ w: ASRWord, _ isFinal: Bool) -> ReconToken {
        ReconToken(id: newId(), text: w.text, state: isFinal ? .final : .volatile, confidence: w.confidence, start: w.start, end: w.end)
    }

    private func ingestDraft(_ words: [ASRWord], _ isFinal: Bool) {
        let base = activeStart
        for i in words.indices {
            let w = words[i]
            let idx = base + i
            if idx < tokens.count {
                tokens[idx].text = w.text
                if let c = w.confidence { tokens[idx].confidence = c }
                if let s = w.start { tokens[idx].start = s }
                if let e = w.end { tokens[idx].end = e }
            } else {
                tokens.append(makeToken(w, false))
            }
        }
        if base + words.count < tokens.count {
            tokens.removeLast(tokens.count - (base + words.count))
        }
        if isFinal {
            for i in base..<tokens.count { tokens[i].state = .final }
            activeStart = tokens.count
        }
    }

    private func ingestRefined(_ words: [ASRWord], _ isFinal: Bool) {
        let haveTimes = !words.isEmpty && words.allSatisfy { $0.start != nil && $0.end != nil }
        let region = Array(tokens[activeStart...])
        var rebuilt: [ReconToken] = []
        var i = 0
        var j = 0
        while i < words.count || j < region.count {
            if i < words.count, j < region.count {
                let w = words[i]
                var tk = region[j]
                let pair = haveTimes
                    ? overlap(w.start!, w.end!, tk.start ?? -Double.infinity, tk.end ?? Double.infinity) > 0
                    : true
                if pair {
                    tk.text = w.text
                    tk.confidence = w.confidence ?? 0.95
                    if haveTimes { tk.start = w.start; tk.end = w.end }
                    rebuilt.append(tk)
                    i += 1
                    j += 1
                } else if haveTimes, w.end! <= (tk.start ?? Double.infinity) {
                    rebuilt.append(makeToken(w, isFinal))
                    i += 1
                } else {
                    j += 1
                }
            } else if i < words.count {
                rebuilt.append(makeToken(words[i], isFinal))
                i += 1
            } else {
                j += 1
            }
        }
        tokens.removeSubrange(activeStart..<tokens.count)
        tokens.append(contentsOf: rebuilt)
        if isFinal {
            for k in activeStart..<tokens.count { tokens[k].state = .final }
            activeStart = tokens.count
        }
    }
}

func overlap(_ a0: Double, _ a1: Double, _ b0: Double, _ b1: Double) -> Double {
    max(0, min(a1, b1) - max(a0, b0))
}
