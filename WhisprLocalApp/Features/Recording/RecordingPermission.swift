import AVFoundation
import Foundation

/// User's microphone permission as surfaced to the recording UI.
///
/// Maps AVFoundation's permission enum to the three states the UI actually
/// needs to render: ask, record, or guide the user to Settings.
enum RecordingPermissionStatus: Equatable {
    case notDetermined
    case granted
    case denied
}

/// Injectable seam over `AVAudioApplication`'s permission API so the UI
/// layer can be exercised without touching AVFoundation.
protocol RecordingPermissionAuthority {
    var currentStatus: RecordingPermissionStatus { get }
    func request() async -> RecordingPermissionStatus
}

/// Production implementation. Uses the iOS-17 `AVAudioApplication` API —
/// the older `AVAudioSession.requestRecordPermission(_:)` is deprecated.
struct AVRecordingPermissionAuthority: RecordingPermissionAuthority {

    var currentStatus: RecordingPermissionStatus {
        Self.map(AVAudioApplication.shared.recordPermission)
    }

    func request() async -> RecordingPermissionStatus {
        // AVAudioApplication.requestRecordPermission ships only in its
        // completion-handler form on iOS 17; bridge to async explicitly.
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted ? .granted : .denied)
            }
        }
    }

    static func map(_ status: AVAudioApplication.recordPermission) -> RecordingPermissionStatus {
        switch status {
        case .undetermined: return .notDetermined
        case .denied: return .denied
        case .granted: return .granted
        @unknown default: return .denied
        }
    }
}
