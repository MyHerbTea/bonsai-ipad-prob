import Foundation

/// Build93 experimental 32K prefill shape. This policy never changes an active llama context.
/// A candidate trial is marked pending before context creation. If the process exits
/// without completing a substantial successful text request, the next process falls
/// back to 4/4. An unclean exit does not, by itself, prove Jetsam or an OOM.
enum Build93BatchTrialPolicy {
    enum Selection: String {
        case candidate8 = "candidate_8_8"
        case fallback4 = "fallback_4_4"
        case notApplicable = "not_applicable"
    }

    static let pendingKey = "BonsaiBuild93CandidatePending"
    static let fallbackKey = "BonsaiBuild93StickyFallback"
    static let confirmedKey = "BonsaiBuild93CandidateConfirmed"
    static let reasonKey = "BonsaiBuild93SelectionReason"
    static let modeKey = "BonsaiBuild93SelectedMode"

    private static let gate = NSLock()
    private static var currentSelection: Selection?

    static func select(context: Int, defaults: UserDefaults = .standard) -> Selection {
        guard context == 32_768 else { return .notApplicable }
        gate.lock()
        defer { gate.unlock() }
        if let currentSelection { return currentSelection }

        if defaults.bool(forKey: fallbackKey) {
            defaults.set(Selection.fallback4.rawValue, forKey: modeKey)
            defaults.set("sticky_recovery_baseline", forKey: reasonKey)
            currentSelection = .fallback4
        } else if defaults.bool(forKey: pendingKey) {
            // Previous process never certified its experimental inference run.
            defaults.set(true, forKey: fallbackKey)
            defaults.set(false, forKey: pendingKey)
            defaults.set(Selection.fallback4.rawValue, forKey: modeKey)
            defaults.set("prior_candidate_attempt_incomplete", forKey: reasonKey)
            currentSelection = .fallback4
        } else {
            // Arm the rollback marker before model/context allocation begins.
            defaults.set(true, forKey: pendingKey)
            defaults.set(Selection.candidate8.rawValue, forKey: modeKey)
            defaults.set("candidate_awaiting_1024_token_text_success", forKey: reasonKey)
            currentSelection = .candidate8
        }
        defaults.synchronize()
        return currentSelection!
    }

    /// Successful completion (not just prefill progress) of a real >=1024-token
    /// API text request retires the tentative rollback marker. This is only an
    /// experiment checkpoint, not full stability or production certification.
    static func noteSuccessfulText(promptTokens: Int, defaults: UserDefaults = .standard) {
        gate.lock()
        defer { gate.unlock() }
        guard currentSelection == .candidate8,
              promptTokens >= 1024,
              defaults.bool(forKey: pendingKey)
        else { return }
        defaults.set(false, forKey: pendingKey)
        defaults.set(true, forKey: confirmedKey)
        defaults.set("candidate_completed_1024_token_text_request", forKey: reasonKey)
        defaults.synchronize()
    }

    /// Called only when the experimental API startup/context path fails.
    /// The next authorized start uses baseline; do not retry loading in a loop.
    static func noteStartupFailure(defaults: UserDefaults = .standard) {
        gate.lock()
        defer { gate.unlock() }
        guard currentSelection == .candidate8 else { return }
        defaults.set(true, forKey: fallbackKey)
        defaults.set(false, forKey: pendingKey)
        defaults.set("candidate_startup_failed", forKey: reasonKey)
        defaults.synchronize()
    }

#if DEBUG
    static func resetProcessSelectionForTests() {
        gate.lock()
        currentSelection = nil
        gate.unlock()
    }
#endif
}
