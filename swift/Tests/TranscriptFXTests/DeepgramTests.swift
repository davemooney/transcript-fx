import XCTest
@testable import TranscriptFX

@MainActor
final class DeepgramTests: XCTestCase {
    final class Recorder: TranscriptSink {
        var ops: [String] = []
        func append(_ id: String, _ text: String, confidence: Double?) { ops.append("append \(id) \(text)") }
        func revise(_ id: String, _ text: String) { ops.append("revise \(id) \(text)") }
        func remove(_ id: String) { ops.append("remove \(id)") }
    }

    private func result(_ words: [String], final: Bool = false) -> Data {
        let ws = words.map { "{\"word\":\"\($0)\",\"confidence\":0.9}" }.joined(separator: ",")
        let json = "{\"channel\":{\"alternatives\":[{\"transcript\":\"\(words.joined(separator: " "))\",\"confidence\":0.9,\"words\":[\(ws)]}]},\"is_final\":\(final)}"
        return Data(json.utf8)
    }

    func testRefinementAndCommit() {
        let rec = Recorder()
        let dg = DeepgramConsumer(sink: rec)
        dg.apply(jsonData: result(["set", "a"]))
        dg.apply(jsonData: result(["said", "a"]))
        dg.apply(jsonData: result(["said", "a", "timer"]))
        dg.apply(jsonData: result(["said", "a", "timer"], final: true))
        dg.apply(jsonData: result(["for"]))
        XCTAssertEqual(rec.ops, [
            "append 0-0 set", "append 0-1 a",
            "revise 0-0 said",
            "append 0-2 timer",
            "append 1-0 for",
        ])
    }

    func testInterimShrink() {
        let rec = Recorder()
        let dg = DeepgramConsumer(sink: rec)
        dg.apply(jsonData: result(["the", "quick", "brownn"]))
        dg.apply(jsonData: result(["the", "quick"]))
        XCTAssertEqual(rec.ops, [
            "append 0-0 the", "append 0-1 quick", "append 0-2 brownn",
            "remove 0-2",
        ])
    }
}
