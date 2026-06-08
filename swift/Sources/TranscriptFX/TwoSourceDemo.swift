#if DEBUG
import SwiftUI

/// SwiftUI mirror of the web two-source demo: a fast draft + a slow refiner
/// combined through the same `TranscriptReconciler`, rendered by `RevisingText`.
/// Open in Xcode to watch it run.
#Preview("Two sources") {
    TwoSourcePreview()
        .frame(width: 560, height: 320)
        .background(Color.black)
}

private enum Phase { case idle, draft, refined }

private struct TwoSourcePreview: View {
    @State private var tokens: [Token] = []
    @State private var phase: Phase = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Label("Parakeet · draft", systemImage: "bolt.fill")
                    .foregroundStyle(phase == .draft ? Color.yellow : Color.secondary)
                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                Label("Whisper · refiner", systemImage: "sparkles")
                    .foregroundStyle(phase == .refined ? Color.green : Color.secondary)
            }
            .font(.caption.weight(.medium))

            RevisingText(tokens: tokens, baseFontSize: 26)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(28)
        .task { await run() }
    }

    private func run() async {
        let recon = TranscriptReconciler()
        func push() {
            tokens = recon.tokens.map { Token(id: $0.id, text: $0.text, state: $0.state, confidence: $0.confidence) }
        }
        func sleep(_ ms: UInt64) async -> Bool {
            try? await Task.sleep(for: .milliseconds(ms))
            return Task.isCancelled
        }

        let draft: [ASRWord] = [
            ASRWord(text: "their", start: 0.0, end: 0.4, confidence: 0.5),
            ASRWord(text: "meeting", start: 0.4, end: 0.9, confidence: 0.7),
            ASRWord(text: "is", start: 0.9, end: 1.1, confidence: 0.55),
            ASRWord(text: "at", start: 1.1, end: 1.4, confidence: 0.5),
            ASRWord(text: "too", start: 1.4, end: 1.8, confidence: 0.4),
            ASRWord(text: "thirty", start: 1.8, end: 2.2, confidence: 0.6),
        ]
        let refined: [ASRWord] = [
            ASRWord(text: "there", start: 0.0, end: 0.4, confidence: 0.98),
            ASRWord(text: "meeting", start: 0.4, end: 0.9, confidence: 0.98),
            ASRWord(text: "is", start: 0.9, end: 1.1, confidence: 0.98),
            ASRWord(text: "at", start: 1.1, end: 1.4, confidence: 0.98),
            ASRWord(text: "two", start: 1.4, end: 1.8, confidence: 0.98),
            ASRWord(text: "thirty", start: 1.8, end: 2.2, confidence: 0.98),
        ]

        while !Task.isCancelled {
            recon.reset(); push(); phase = .idle
            if await sleep(700) { return }
            phase = .draft
            for i in 1...draft.count {
                recon.ingest(ASRResult(words: Array(draft[0..<i]), isFinal: false), role: .draft)
                push()
                if await sleep(240) { return }
            }
            if await sleep(1300) { return } // hold the imperfect draft
            phase = .refined
            recon.ingest(ASRResult(words: refined, isFinal: true), role: .refined)
            push()
            if await sleep(2800) { return }
        }
    }
}
#endif
