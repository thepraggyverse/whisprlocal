import XCTest
@testable import WhisprLocalApp

final class ModelEntryTests: XCTestCase {

    private func makeEntry(minRAMBytes: Int64 = 4_000_000_000) -> ModelEntry {
        ModelEntry(
            id: "whisper-small",
            displayName: "Whisper Small",
            variantName: "openai_whisper-small",
            huggingFaceRepo: "argmaxinc/whisperkit-coreml",
            sizeBytes: 250_000_000,
            sha256: nil,
            language: .multilingual,
            minDeviceRAMBytes: minRAMBytes,
            minIOSVersion: "17.0",
            recommendedUse: .stt,
            license: "MIT",
            isDefault: false,
            note: "test"
        )
    }

    func testIsSupportedWhenRAMMeetsMinimum() {
        let entry = makeEntry(minRAMBytes: 4_000_000_000)
        XCTAssertTrue(entry.isSupportedOnDevice(ramBytes: 4_000_000_000))
        XCTAssertTrue(entry.isSupportedOnDevice(ramBytes: 8_000_000_000))
    }

    func testIsNotSupportedWhenRAMBelowMinimum() {
        let entry = makeEntry(minRAMBytes: 4_000_000_000)
        XCTAssertFalse(entry.isSupportedOnDevice(ramBytes: 3_500_000_000))
        XCTAssertFalse(entry.isSupportedOnDevice(ramBytes: 0))
    }

    func testZeroMinimumAcceptsAnyDevice() {
        let entry = makeEntry(minRAMBytes: 0)
        XCTAssertTrue(entry.isSupportedOnDevice(ramBytes: 0))
        XCTAssertTrue(entry.isSupportedOnDevice(ramBytes: 1))
    }

    func testCodableRoundTrip() throws {
        let entry = makeEntry()
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ModelEntry.self, from: data)
        XCTAssertEqual(decoded, entry)
    }

    func testHuggingFaceURLComposition() {
        let entry = makeEntry()
        XCTAssertEqual(
            entry.huggingFaceURL?.absoluteString,
            "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-small"
        )
    }

    func testLanguageEnumDecodesShortCode() throws {
        let json = Data(#"{"language":"en"}"#.utf8)
        struct Holder: Decodable { let language: ModelEntry.Language }
        let decoded = try JSONDecoder().decode(Holder.self, from: json)
        XCTAssertEqual(decoded.language, .english)
    }
}
