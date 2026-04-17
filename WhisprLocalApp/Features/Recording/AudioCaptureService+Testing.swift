#if DEBUG
import AVFoundation
import Foundation

/// Test-only read of `AudioCaptureService`'s internal cleanup-sensitive
/// state. Used by the Bugbot M1 #2 and #4 regression tests to verify
/// `start()`'s failure path and the fileBox clearing contract.
extension AudioCaptureService {

    struct InternalStateSnapshot: Equatable {
        let state: State
        let hasEngine: Bool
        let hasConverter: Bool
        let hasOutputFile: Bool
        let currentFileURL: URL?
        let hasFileBox: Bool
        let boxedFileIsNil: Bool
    }

    var stateSnapshotForTests: InternalStateSnapshot {
        InternalStateSnapshot(
            state: state,
            hasEngine: engine != nil,
            hasConverter: converter != nil,
            hasOutputFile: outputFile != nil,
            currentFileURL: currentFileURL,
            hasFileBox: fileBox != nil,
            boxedFileIsNil: fileBox?.file == nil
        )
    }
}
#endif
