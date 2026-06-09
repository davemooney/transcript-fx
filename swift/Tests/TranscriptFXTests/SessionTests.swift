import XCTest
@testable import TranscriptFX

@MainActor
final class SessionTests: XCTestCase {
    func testIngestPublishesSnapshotAndReportsEvents() {
        let session = TranscriptSession()
        var reported: [[RevisionEvent]] = []
        session.onEvents = { reported.append($0) }

        session.ingest(TranscriptUpdate(text: "hello"))

        XCTAssertEqual(session.snapshot.tokens.map(\.text), ["hello"])
        XCTAssertTrue(session.snapshot.isLive)
        XCTAssertEqual(reported.count, 1)
    }

    func testIngestAcceptsConvertible() {
        struct FakeChunk: TranscriptUpdateConvertible {
            var transcriptUpdate: TranscriptUpdate {
                TranscriptUpdate(text: "from adapter", tier: .refined, isFinal: true)
            }
        }
        let session = TranscriptSession()
        session.ingest(FakeChunk())
        XCTAssertEqual(session.snapshot.tokens.map(\.text), ["from", "adapter"])
        XCTAssertEqual(session.snapshot.tokens.map(\.state), [.finalized, .finalized])
    }

    func testFinalizeAllAndReset() {
        let session = TranscriptSession(configuration: .twoTier)
        session.ingest(TranscriptUpdate(text: "open ended"))
        session.finalizeAll()
        XCTAssertEqual(session.snapshot.tokens.map(\.state), [.finalized, .finalized])
        XCTAssertFalse(session.snapshot.isLive)

        session.reset()
        XCTAssertEqual(session.snapshot, .empty)
    }
}
