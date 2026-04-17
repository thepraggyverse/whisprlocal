import XCTest
@testable import WhisprLocalApp

final class ModelCatalogTests: XCTestCase {

    // MARK: - Bundled catalog invariants

    func testBundledCatalogLoads() throws {
        let catalog = try ModelCatalog.loadBundled()
        XCTAssertEqual(catalog.schemaVersion, 1)
    }

    func testBundledCatalogShipsFourEntries() throws {
        let catalog = try ModelCatalog.loadBundled()
        XCTAssertEqual(catalog.entries.count, 4)
    }

    func testBundledCatalogExpectedIDs() throws {
        let catalog = try ModelCatalog.loadBundled()
        let ids = Set(catalog.entries.map(\.id))
        XCTAssertEqual(
            ids,
            ["whisper-tiny-en", "whisper-base", "whisper-small", "whisper-large-v3-turbo"]
        )
    }

    func testBundledDefaultIsWhisperBase() throws {
        let catalog = try ModelCatalog.loadBundled()
        XCTAssertEqual(catalog.defaultEntry?.id, "whisper-base")
    }

    func testBundledDefaultIsMultilingual() throws {
        let catalog = try ModelCatalog.loadBundled()
        XCTAssertEqual(catalog.defaultEntry?.language, .multilingual)
    }

    func testBundledEntriesHaveRequiredFields() throws {
        let catalog = try ModelCatalog.loadBundled()
        for entry in catalog.entries {
            XCTAssertFalse(entry.displayName.isEmpty, "\(entry.id): displayName")
            XCTAssertFalse(entry.variantName.isEmpty, "\(entry.id): variantName")
            XCTAssertFalse(entry.huggingFaceRepo.isEmpty, "\(entry.id): huggingFaceRepo")
            XCTAssertGreaterThan(entry.sizeBytes, 0, "\(entry.id): sizeBytes must be positive")
            XCTAssertFalse(entry.license.isEmpty, "\(entry.id): license")
        }
    }

    func testAllBundledEntriesAreSTT() throws {
        let catalog = try ModelCatalog.loadBundled()
        for entry in catalog.entries {
            XCTAssertEqual(entry.recommendedUse, .stt, "\(entry.id) is not stt — polish/command land in M3+")
        }
    }

    func testEntryLookupById() throws {
        let catalog = try ModelCatalog.loadBundled()
        XCTAssertNotNil(catalog.entry(id: "whisper-base"))
        XCTAssertNil(catalog.entry(id: "does-not-exist"))
    }

    // MARK: - Device capability filter

    func testSupportedFilterExcludesLargeTurboOnMidRangeDevice() throws {
        let catalog = try ModelCatalog.loadBundled()
        // 6 GB device (A15 Pro, A16 non-Pro) — large-v3-turbo requires 8 GB.
        let supported = catalog.supported(onDeviceRAMBytes: 6_000_000_000)
        XCTAssertFalse(supported.contains(where: { $0.id == "whisper-large-v3-turbo" }))
        XCTAssertTrue(supported.contains(where: { $0.id == "whisper-base" }))
        XCTAssertTrue(supported.contains(where: { $0.id == "whisper-small" }))
    }

    func testSupportedFilterIncludesLargeTurboOn8GBDevice() throws {
        let catalog = try ModelCatalog.loadBundled()
        let supported = catalog.supported(onDeviceRAMBytes: 8_000_000_000)
        XCTAssertTrue(supported.contains(where: { $0.id == "whisper-large-v3-turbo" }))
    }

    func testSupportedFilterOnLowRAMDeviceRetainsTinyAndBase() throws {
        let catalog = try ModelCatalog.loadBundled()
        // 3 GB device (theoretical floor) — small and large need more.
        let supported = catalog.supported(onDeviceRAMBytes: 3_000_000_000)
        let ids = Set(supported.map(\.id))
        XCTAssertEqual(ids, ["whisper-tiny-en", "whisper-base"])
    }

    // MARK: - Loader error paths

    func testRejectsUnsupportedSchemaVersion() {
        let json = Data(#"{"schemaVersion": 999, "models": []}"#.utf8)
        XCTAssertThrowsError(try ModelCatalog.load(from: json)) { error in
            guard case ModelCatalog.LoadError.unsupportedSchemaVersion(let version) = error else {
                return XCTFail("expected unsupportedSchemaVersion, got \(error)")
            }
            XCTAssertEqual(version, 999)
        }
    }

    func testRejectsCatalogWithoutDefault() {
        let json = Data("""
        {
          "schemaVersion": 1,
          "models": [
            {
              "id": "a", "displayName": "A", "variantName": "x",
              "huggingFaceRepo": "r", "sizeBytes": 1, "sha256": null,
              "language": "en", "minDeviceRAMBytes": 0, "minIOSVersion": "17.0",
              "recommendedUse": "stt", "license": "MIT", "isDefault": false, "note": ""
            }
          ]
        }
        """.utf8)
        XCTAssertThrowsError(try ModelCatalog.load(from: json)) { error in
            XCTAssertEqual(error as? ModelCatalog.LoadError, .noDefaultEntry)
        }
    }

    func testRejectsCatalogWithTwoDefaults() {
        let entryJSON: (String, Bool) -> String = { id, isDefault in
            """
            {
              "id": "\(id)", "displayName": "\(id)", "variantName": "x",
              "huggingFaceRepo": "r", "sizeBytes": 1, "sha256": null,
              "language": "en", "minDeviceRAMBytes": 0, "minIOSVersion": "17.0",
              "recommendedUse": "stt", "license": "MIT", "isDefault": \(isDefault), "note": ""
            }
            """
        }
        let json = Data("""
        {
          "schemaVersion": 1,
          "models": [\(entryJSON("a", true)), \(entryJSON("b", true))]
        }
        """.utf8)
        XCTAssertThrowsError(try ModelCatalog.load(from: json)) { error in
            guard case ModelCatalog.LoadError.multipleDefaultEntries(let ids) = error else {
                return XCTFail("expected multipleDefaultEntries, got \(error)")
            }
            XCTAssertEqual(Set(ids), ["a", "b"])
        }
    }
}
