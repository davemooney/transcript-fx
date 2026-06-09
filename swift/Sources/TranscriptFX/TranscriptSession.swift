import SwiftUI

/// The one object a downstream app talks to. Feed it normalized
/// `TranscriptUpdate`s from any ASR; observe `snapshot` (or just hand it to
/// `TranscriptView`) and the transcript animates itself.
///
///     @StateObject private var session = TranscriptSession(configuration: .twoTier)
///
///     var body: some View {
///         TranscriptView(snapshot: session.snapshot)
///     }
///
///     // tier-1 fast preview:
///     session.ingest(TranscriptUpdate(words: previewWords, tier: .preview, isFinal: utteranceDone))
///     // tier-2 refinement, whenever it lands:
///     session.ingest(TranscriptUpdate(words: refinedWords, tier: .refined, isFinal: true))
@MainActor
public final class TranscriptSession: ObservableObject {
    @Published public private(set) var snapshot: TranscriptSnapshot = .empty

    /// Optional hook: the semantic changes each update caused (for haptics,
    /// accessibility announcements, logging, …).
    public var onEvents: (([RevisionEvent]) -> Void)?

    private let reconciler: TranscriptReconciler

    public init(configuration: ReconcilerConfiguration = ReconcilerConfiguration()) {
        self.reconciler = TranscriptReconciler(configuration: configuration)
    }

    /// Apply one update; returns (and reports) the revision events it caused.
    @discardableResult
    public func ingest(_ update: some TranscriptUpdateConvertible) -> [RevisionEvent] {
        let events = reconciler.apply(update.transcriptUpdate)
        snapshot = reconciler.snapshot
        if !events.isEmpty {
            onEvents?(events)
        }
        return events
    }

    /// Commit the whole transcript (e.g. when the recording stops).
    @discardableResult
    public func finalizeAll() -> [RevisionEvent] {
        let events = reconciler.finalizeAll()
        snapshot = reconciler.snapshot
        if !events.isEmpty {
            onEvents?(events)
        }
        return events
    }

    public func reset() {
        reconciler.reset()
        snapshot = .empty
    }
}
