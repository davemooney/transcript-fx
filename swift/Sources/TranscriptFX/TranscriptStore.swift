import SwiftUI

/// The reactive drop-in. A SwiftUI-observable transcript backed by the reconciler —
/// feed it ASR results from any source and bind `tokens` to `RevisingText`.
///
///   @StateObject private var transcript = TranscriptStore()
///
///   RevisingText(tokens: transcript.tokens)
///
///   // …from any ASR source:
///   transcript.ingest(speechResultToASR(result))                       // Apple
///   transcript.ingest(whisperKitToASR(seg.words ?? [], isFinal: true), // WhisperKit
///                     role: .refined)
///   transcript.ingest(myLocalResult, role: .draft)                     // your local rig
@MainActor
public final class TranscriptStore: ObservableObject {
    @Published public private(set) var tokens: [Token] = []
    private let reconciler = TranscriptReconciler()

    public init() {}

    /// Feed one ASR result. `role: .draft` (fast) or `.refined` (slow/accurate).
    public func ingest(_ result: ASRResult, role: SourceRole = .draft) {
        reconciler.ingest(result, role: role)
        tokens = reconciler.tokens.map(Token.init)
    }

    public func reset() {
        reconciler.reset()
        tokens = []
    }
}
