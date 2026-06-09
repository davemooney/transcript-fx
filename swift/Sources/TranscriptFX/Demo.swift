#if DEBUG
import SwiftUI

/// Scripted end-to-end demo: a fast preview tier streams two speakers'
/// words; the refined tier lands later and corrects in place — including a
/// merge ("too thirty" → "2:30.") and punctuation that settles sentences and
/// paragraphs. Open this file in Xcode and run the preview.
#Preview("Two-tier live transcript") {
    TranscriptDemo()
        .frame(width: 600, height: 460)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
}

private struct TranscriptDemo: View {
    @StateObject private var session = TranscriptSession(configuration: .twoTier)
    @State private var mode: RenderingMode = .liveRevision

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Mode", selection: $mode) {
                Text("Preview").tag(RenderingMode.livePreview)
                Text("Revision").tag(RenderingMode.liveRevision)
                Text("Final").tag(RenderingMode.finalText)
                Text("Debug").tag(RenderingMode.debug)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 380)

            ScrollView {
                TranscriptView(snapshot: session.snapshot, mode: mode)
            }
        }
        .padding(24)
        .task { await runScript() }
    }

    private func runScript() async {
        func wait(_ ms: UInt64) async -> Bool {
            try? await Task.sleep(for: .milliseconds(ms))
            return Task.isCancelled
        }
        func word(_ t: String, _ s: Double, _ e: Double, _ c: Double) -> TranscriptWord {
            TranscriptWord(text: t, start: s, end: e, confidence: c)
        }

        let alicePreview = [
            word("their", 0.0, 0.4, 0.45), word("meeting", 0.4, 0.9, 0.7),
            word("is", 0.9, 1.1, 0.6), word("at", 1.1, 1.4, 0.55),
            word("too", 1.4, 1.8, 0.4), word("thirty", 1.8, 2.2, 0.6),
        ]
        let aliceRefined = [
            word("Their", 0.0, 0.4, 0.98), word("meeting", 0.4, 0.9, 0.98),
            word("is", 0.9, 1.1, 0.98), word("at", 1.1, 1.4, 0.98),
            word("2:30.", 1.4, 2.2, 0.97), // merges "too thirty"
        ]
        let bobPreview = [
            word("okay", 4.5, 4.8, 0.8), word("grate", 4.8, 5.2, 0.4),
            word("lets", 5.2, 5.5, 0.5), word("lock", 5.5, 5.8, 0.7),
            word("it", 5.8, 5.9, 0.8), word("in", 5.9, 6.1, 0.8),
        ]
        let bobRefined = [
            word("Okay,", 4.5, 4.8, 0.98), word("great.", 4.8, 5.2, 0.97),
            word("Let's", 5.2, 5.5, 0.98), word("lock", 5.5, 5.8, 0.98),
            word("it", 5.8, 5.9, 0.98), word("in.", 5.9, 6.1, 0.98),
        ]

        while !Task.isCancelled {
            session.reset()
            if await wait(700) { return }

            // Alice streams (tier-1 live preview).
            for i in 1...alicePreview.count {
                session.ingest(TranscriptUpdate(
                    words: Array(alicePreview.prefix(i)),
                    utteranceID: "u1", speaker: "Alice"
                ))
                if await wait(230) { return }
            }
            session.ingest(TranscriptUpdate(
                words: alicePreview, isFinal: true, utteranceID: "u1", speaker: "Alice"
            ))
            if await wait(800) { return }

            // Bob starts a new paragraph (speaker change) while Alice's
            // tier-2 refinement is still in flight.
            for i in 1...3 {
                session.ingest(TranscriptUpdate(
                    words: Array(bobPreview.prefix(i)),
                    utteranceID: "u2", speaker: "Bob"
                ))
                if await wait(230) { return }
            }

            // Alice's refinement lands mid-stream: in-place morphs, the
            // "too thirty" → "2:30." merge, and her sentence settles.
            session.ingest(TranscriptUpdate(
                words: aliceRefined, tier: .refined, isFinal: true,
                utteranceID: "u1", speaker: "Alice"
            ))

            for i in 4...bobPreview.count {
                session.ingest(TranscriptUpdate(
                    words: Array(bobPreview.prefix(i)),
                    utteranceID: "u2", speaker: "Bob"
                ))
                if await wait(230) { return }
            }
            session.ingest(TranscriptUpdate(
                words: bobPreview, isFinal: true, utteranceID: "u2", speaker: "Bob"
            ))
            if await wait(1100) { return }

            // Bob's refinement: corrections plus punctuation that splits his
            // paragraph into two settled sentences.
            session.ingest(TranscriptUpdate(
                words: bobRefined, tier: .refined, isFinal: true,
                utteranceID: "u2", speaker: "Bob"
            ))
            if await wait(3500) { return }
        }
    }
}
#endif
