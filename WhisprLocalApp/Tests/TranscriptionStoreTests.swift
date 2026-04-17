import XCTest
@testable import WhisprLocalApp

@MainActor
final class TranscriptionStoreTests: XCTestCase {

    func testInitiallyEmpty() {
        let store = TranscriptionStore()
        XCTAssertTrue(store.outcomes.isEmpty)
        XCTAssertNil(store.latest)
    }

    func testAppendMakesOutcomeLatest() {
        let store = TranscriptionStore()
        store.append(makeOutcome(text: "first"))
        store.append(makeOutcome(text: "second"))
        XCTAssertEqual(store.latest?.rawText, "second")
        XCTAssertEqual(store.outcomes.map(\.rawText), ["second", "first"])
    }

    func testAppendRespectsMaxOutcomesCap() {
        let store = TranscriptionStore()
        let cap = TranscriptionStore.maxOutcomes
        for index in 0..<(cap + 10) {
            store.append(makeOutcome(text: "#\(index)"))
        }
        XCTAssertEqual(store.outcomes.count, cap)
        // Newest at index 0 — the most recent append should still be at the top.
        XCTAssertEqual(store.latest?.rawText, "#\(cap + 9)")
        // Oldest kept outcome: #10 (0..<9 dropped).
        XCTAssertEqual(store.outcomes.last?.rawText, "#10")
    }

    func testClearAllEmptiesStore() {
        let store = TranscriptionStore()
        store.append(makeOutcome(text: "keep me"))
        store.clearAll()
        XCTAssertTrue(store.outcomes.isEmpty)
        XCTAssertNil(store.latest)
    }

    // MARK: - Helpers

    private func makeOutcome(text: String) -> TranscriptionOutcome {
        TranscriptionOutcome(
            modelId: "whisper-base",
            audioURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).wav"),
            rawText: text,
            detectedLanguage: "en",
            durationSeconds: 0.1,
            createdAt: Date()
        )
    }
}
