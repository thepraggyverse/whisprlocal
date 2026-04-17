import Foundation
import Observation

/// In-memory, most-recent-first log of `TranscriptionOutcome`s produced
/// by the `InboxJobWatcher`. The Record screen observes `latest`; the
/// (forthcoming M6) History screen will observe `outcomes` directly.
///
/// **Scope limit.** This store does not persist across app launches. M6
/// replaces it with a SwiftData-backed history per spec §5.4 + §11. The
/// outcome cap matches §5.4's "last 100 sessions" so the replacement
/// will inherit the same retention ceiling.
@Observable
@MainActor
final class TranscriptionStore {

    /// Most-recent-first. Capped at `maxOutcomes`.
    private(set) var outcomes: [TranscriptionOutcome] = []

    /// Retention ceiling. Matches spec §5.4 "last 100 sessions".
    static let maxOutcomes = 100

    var latest: TranscriptionOutcome? {
        outcomes.first
    }

    func append(_ outcome: TranscriptionOutcome) {
        outcomes.insert(outcome, at: 0)
        if outcomes.count > Self.maxOutcomes {
            outcomes.removeLast(outcomes.count - Self.maxOutcomes)
        }
    }

    func clearAll() {
        outcomes.removeAll()
    }
}
