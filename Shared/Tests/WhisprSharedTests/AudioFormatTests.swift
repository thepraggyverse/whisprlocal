import XCTest
@testable import WhisprShared

final class AudioFormatTests: XCTestCase {

    func testWhisperCompatibleConstants() {
        XCTAssertEqual(AudioFormat.sampleRate, 16_000)
        XCTAssertEqual(AudioFormat.channelCount, 1)
        XCTAssertEqual(AudioFormat.bitDepth, 32)
    }
}
