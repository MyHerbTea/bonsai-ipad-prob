import Foundation

/// Bounded Build94 experiment selection. Changes are consumed on the next *process* launch.
/// A failed or incomplete 16/16 attempt permanently returns to 4/4 until explicitly acknowledged.
/// Nothing in this policy can change an already allocated llama context.
enum Build94BatchExperiment {
    enum Arm: String {
        case safe4 = "SAFE4"
        case baseline8 = "BASELINE8"
        case candidate16 = "CANDIDATE16"
    }

    static let nextKey = "BonsaiBuild94NextArm"
    static let activeKey = "BonsaiBuild94ActiveArm"
    static let pendingKey = "BonsaiBuild94CandidatePending"
    static let fallbackKey = "BonsaiBuild94StickyFallback"
    static let confirmedKey = "BonsaiBuild94CandidateCompleted"
    static let reasonKey = "BonsaiBuild94DecisionReason"
    static let baselineOKKey = "BonsaiBuild94BaselineCompleted"
    private static let gate = NSLock()
    private static var selected: Arm?

    static func select(context: Int, defaults: UserDefaults = .standard) -> Arm? {
        guard context == 32_768 else { return nil }
        gate.lock()
        defer { gate.unlock() }
        if let selected { return selected }

        let arm: Arm
        if defaults.bool(forKey: fallbackKey) ||
            defaults.bool(forKey: Build93BatchTrialPolicy.fallbackKey) {
            arm = .safe4
            defaults.set(true, forKey: fallbackKey)
            defaults.set("sticky_recovery_baseline", forKey: reasonKey)
        } else if defaults.bool(forKey: pendingKey) {
            arm = .safe4
            defaults.set(true, forKey: fallbackKey)
            defaults.set(false, forKey: pendingKey)
            defaults.set("previous_candidate16_incomplete", forKey: reasonKey)
        } else {
            let planned = Arm(rawValue: defaults.string(forKey: nextKey) ?? "") ?? .baseline8
            // Never silently make 16/16 the product default.
            defaults.set(Arm.baseline8.rawValue, forKey: nextKey)
            arm = planned
            if arm == .candidate16 {
                // Persist marker BEFORE model/context creation.
                defaults.set(true, forKey: pendingKey)
                defaults.set(false, forKey: confirmedKey)
                defaults.set("candidate16_trial_pending", forKey: reasonKey)
            } else {
                defaults.set("selected_\(arm.rawValue)", forKey: reasonKey)
            }
        }
        defaults.set(arm.rawValue, forKey: activeKey)
        defaults.synchronize()
        selected = arm
        return arm
    }

    static func scheduleNext(_ arm: Arm, acknowledgeRecovery: Bool,
                             defaults: UserDefaults = .standard) -> Bool {
        gate.lock()
        defer { gate.unlock() }
        let fallback = defaults.bool(forKey: fallbackKey) ||
            defaults.bool(forKey: Build93BatchTrialPolicy.fallbackKey)
        if fallback && (arm != .safe4) && !acknowledgeRecovery {
            return false
        }
        // Recovery must be deliberate; candidate16 must follow a verified baseline8.
        if arm == .candidate16 && !defaults.bool(forKey: baselineOKKey) {
            return false
        }
        if acknowledgeRecovery && arm == .baseline8 {
            defaults.set(false, forKey: fallbackKey)
            defaults.set(false, forKey: Build93BatchTrialPolicy.fallbackKey)
            defaults.set(false, forKey: Build93BatchTrialPolicy.pendingKey)
            defaults.set(false, forKey: pendingKey)
            defaults.set("manual_recovery_acknowledged", forKey: reasonKey)
        }
        defaults.set(arm.rawValue, forKey: nextKey)
        defaults.synchronize()
        return true
    }

    static func noteTextSuccess(promptTokens: Int, defaults: UserDefaults = .standard) {
        guard promptTokens >= 200 else { return }
        gate.lock()
        defer { gate.unlock() }
        if selected == .baseline8 {
            defaults.set(true, forKey: baselineOKKey)
        } else if selected == .candidate16 && defaults.bool(forKey: pendingKey) {
            defaults.set(false, forKey: pendingKey)
            defaults.set(true, forKey: confirmedKey)
            defaults.set("candidate16_completed_text_200", forKey: reasonKey)
        }
        defaults.synchronize()
    }

    static func noteStartupFailure(defaults: UserDefaults = .standard) {
        gate.lock()
        defer { gate.unlock() }
        guard selected == .candidate16 else { return }
        defaults.set(true, forKey: fallbackKey)
        defaults.set(false, forKey: pendingKey)
        defaults.set(Arm.safe4.rawValue, forKey: nextKey)
        defaults.set("candidate16_startup_failed", forKey: reasonKey)
        defaults.synchronize()
    }

    static func snapshot(defaults: UserDefaults = .standard) -> [String: Any] {
        gate.lock()
        defer { gate.unlock() }
        return [
            "active_arm": selected?.rawValue ?? "NOT_SELECTED",
            "next_arm": defaults.string(forKey: nextKey) ?? Arm.baseline8.rawValue,
            "restart_required": (defaults.string(forKey: nextKey) ?? Arm.baseline8.rawValue) !=
                (selected?.rawValue ?? Arm.baseline8.rawValue),
            "pending": defaults.bool(forKey: pendingKey),
            "confirmed_candidate16": defaults.bool(forKey: confirmedKey),
            "baseline8_completed": defaults.bool(forKey: baselineOKKey),
            "sticky_fallback": defaults.bool(forKey: fallbackKey),
            "reason": defaults.string(forKey: reasonKey) ?? "none"
        ]
    }

#if DEBUG
    static func resetForTests() {
        gate.lock()
        selected = nil
        gate.unlock()
    }
#endif
}
