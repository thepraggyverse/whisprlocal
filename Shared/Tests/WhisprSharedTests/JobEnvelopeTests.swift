import XCTest
@testable import WhisprShared

final class JobEnvelopeTests: XCTestCase {

    func testRoundTripCodable() throws {
        let original = JobEnvelope(
            sourceBundleId: "com.example.TextEdit",
            pipeline: "email"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JobEnvelope.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.pipeline, "email")
        XCTAssertEqual(decoded.sourceBundleId, "com.example.TextEdit")
    }

    func testDefaultPipelineIsDefault() {
        let envelope = JobEnvelope()
        XCTAssertEqual(envelope.pipeline, "default")
        XCTAssertNil(envelope.sourceBundleId)
    }
}
