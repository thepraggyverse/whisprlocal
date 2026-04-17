import UIKit
import OSLog
import WhisprShared

/// Root view controller for the WhisprKeyboard extension.
///
/// At M0, this is a placeholder — mic capture lands at M4. The class exists
/// so iOS has a principal class to instantiate (declared in Info.plist's
/// `NSExtensionPrincipalClass`) and so `xcodebuild -scheme WhisprKeyboard
/// build` produces a valid `.appex` end-to-end.
///
/// - Important: Do not import WhisperKit, MLX, MLXLLM, MLXLMCommon, MLXNN,
///   or Vision/NaturalLanguage here. The keyboard extension is hard-capped
///   at ~48 MB of RAM by iOS and loading those frameworks blows the ceiling
///   at launch. All ML work happens in the main app; the keyboard's only
///   job is capture → App Group write → insert. See PROJECT_SPEC.md §2,
///   `/audit-privacy`, and `/memory-check`.
final class KeyboardViewController: UIInputViewController {

    private let logger = Logger(
        subsystem: "com.praggy.whisprlocal.keyboard",
        category: "lifecycle"
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.debug("KeyboardViewController did load — M0 placeholder")
        installPlaceholderView()
    }

    private func installPlaceholderView() {
        let label = UILabel()
        label.text = "WhisprLocal"
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .title2)
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isAccessibilityElement = true
        label.accessibilityLabel = "WhisprLocal keyboard — M0 placeholder"
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        // Ensure the IPC primitives resolve at compile time. No work done here;
        // kept as a linker anchor for WhisprShared so the keyboard's dependency
        // on it is covered by build-time checks.
        _ = AppGroupPaths.identifier
    }
}
