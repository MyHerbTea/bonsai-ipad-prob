import Foundation

/// Bounded Build94 experiment selection. Changes are consumed on the next *process* launch.
/// A failed or incomplete 16/16 attempt permanently returns to 4/4 until explicitly acknowledged.
/// Nothing in this policy can change an already allocated llama context.
enum Build94BatchExperiment {
    enum Arm: String {
        case safe4 = "SAFE4"
        case baseline8 = "BASELINE8"
        case candidate16 = "CANDIDATE16"
        // Build102: one-shot bounded experimental arms. Never auto-selected.
        case candidate24 = "CANDIDATE24"
        case candidate32 = "CANDIDATE32"
    }

    static let nextKey = "BonsaiBuild94NextArm"
    static let activeKey = "BonsaiBuild94ActiveArm"
    static let pendingKey = "BonsaiBuild94CandidatePending"
    static let fallbackKey = "BonsaiBuild94StickyFallback"
    static let confirmedKey = "BonsaiBuild94CandidateCompleted"
    static let reasonKey = "BonsaiBuild94DecisionReason"
    static let baselineOKKey = "BonsaiBuild94BaselineCompleted"
    static let candidate24CompletedKey = "BonsaiBuild102Candidate24Completed"
    static let candidate32CompletedKey = "BonsaiBuild102Candidate32Completed"
    static let higherRiskConsentKey = "BonsaiBuild102HigherRiskConsent"
    // Build100 isolated acceleration opt-in. OFF by default on all devices.
    // This is consulted only during 32K context creation, never mid-request.
    static let preferB16Key = "BonsaiBuild100PreferGuardedB16"
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
            defaults.set(false, forKey: preferB16Key)
        } else if defaults.bool(forKey: pendingKey) {
            arm = .safe4
            defaults.set(true, forKey: fallbackKey)
            defaults.set(false, forKey: pendingKey)
            defaults.set("previous_candidate16_incomplete", forKey: reasonKey)
            defaults.set(false, forKey: preferB16Key)
        } else {
            let requested = Arm(rawValue: defaults.string(forKey: nextKey) ?? "")
                ?? .baseline8
            // Explicit opt-in can keep an already-certified candidate across
            // launches. Never auto-rearm an unconfirmed device or a fallback.
            let certified = defaults.bool(forKey: confirmedKey)
                && defaults.bool(forKey: baselineOKKey)
            let preferred = defaults.bool(forKey: preferB16Key)
            let planned: Arm
            if preferred && certified {
                planned = .candidate16
            } else {
                planned = requested
                if preferred && !certified {
                    defaults.set(false, forKey: preferB16Key)
                }
            }
            // One-shot scheduling still reverts, regardless of preference.
            defaults.set(Arm.baseline8.rawValue, forKey: nextKey)
            arm = planned
            if arm == .candidate16 || arm == .candidate24 || arm == .candidate32 {
                // Shared sticky safety marker covers ALL experimental arms.
                // Set BEFORE model/context creation; never change shape mid-process.
                defaults.set(true, forKey: pendingKey)
                if arm == .candidate16 {
                    defaults.set(false, forKey: confirmedKey)
                } else if arm == .candidate24 {
                    defaults.set(false, forKey: candidate24CompletedKey)
                } else {
                    defaults.set(false, forKey: candidate32CompletedKey)
                }
                defaults.set("selected_\(arm.rawValue)_trial_pending", forKey: reasonKey)
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
                             acknowledgeHigherRisk: Bool = false,
                             defaults: UserDefaults = .standard) -> Bool {
        gate.lock()
        defer { gate.unlock() }
        let fallback = defaults.bool(forKey: fallbackKey) ||
            defaults.bool(forKey: Build93BatchTrialPolicy.fallbackKey)
        if fallback && (arm != .safe4) && !acknowledgeRecovery {
            return false
        }
        // B24 requires a prior completed B16 on this installation.
        // B32 additionally requires a completed B24 and explicit consent.
        if arm == .candidate16 && !defaults.bool(forKey: baselineOKKey) {
            return false
        }
        if arm == .candidate24 &&
            (!defaults.bool(forKey: baselineOKKey) ||
             !defaults.bool(forKey: confirmedKey)) {
            return false
        }
        if arm == .candidate32 &&
            (!defaults.bool(forKey: baselineOKKey) ||
             !defaults.bool(forKey: confirmedKey) ||
             !defaults.bool(forKey: candidate24CompletedKey) ||
             !acknowledgeHigherRisk) {
            return false
        }
        if acknowledgeRecovery && arm == .baseline8 {
            defaults.set(false, forKey: fallbackKey)
            defaults.set(false, forKey: Build93BatchTrialPolicy.fallbackKey)
            defaults.set(false, forKey: Build93BatchTrialPolicy.pendingKey)
            defaults.set(false, forKey: pendingKey)
            defaults.set("manual_recovery_acknowledged", forKey: reasonKey)
        }
        if arm != .candidate16 {
            // Explicit experimental scheduling overrides Build100 recurring boost.
            defaults.set(false, forKey: preferB16Key)
        }
        if arm == .candidate32 {
            defaults.set(true, forKey: higherRiskConsentKey)
        } else {
            defaults.set(false, forKey: higherRiskConsentKey)
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
        } else if selected == .candidate24 && defaults.bool(forKey: pendingKey) {
            defaults.set(false, forKey: pendingKey)
            defaults.set(true, forKey: candidate24CompletedKey)
            defaults.set("candidate24_completed_text_200", forKey: reasonKey)
        } else if selected == .candidate32 && defaults.bool(forKey: pendingKey) {
            defaults.set(false, forKey: pendingKey)
            defaults.set(true, forKey: candidate32CompletedKey)
            defaults.set("candidate32_completed_text_200", forKey: reasonKey)
        }
        defaults.synchronize()
    }

    static func noteStartupFailure(defaults: UserDefaults = .standard) {
        gate.lock()
        defer { gate.unlock() }
        guard selected == .candidate16 ||
              selected == .candidate24 ||
              selected == .candidate32
        else { return }
        defaults.set(true, forKey: fallbackKey)
        defaults.set(false, forKey: pendingKey)
        defaults.set(Arm.safe4.rawValue, forKey: nextKey)
        defaults.set("\(selected!.rawValue)_startup_failed", forKey: reasonKey)
        defaults.set(false, forKey: preferB16Key)
        defaults.synchronize()
    }

    static func snapshot(defaults: UserDefaults = .standard) -> [String: Any] {
        gate.lock()
        defer { gate.unlock() }
        let preferred = defaults.bool(forKey: preferB16Key)
        let eligible = defaults.bool(forKey: confirmedKey)
            && defaults.bool(forKey: baselineOKKey)
            && !defaults.bool(forKey: fallbackKey)
            && !defaults.bool(forKey: Build93BatchTrialPolicy.fallbackKey)
        let next = (preferred && eligible)
            ? Arm.candidate16.rawValue
            : (defaults.string(forKey: nextKey) ?? Arm.baseline8.rawValue)
        return [
            "active_arm": selected?.rawValue ?? "NOT_SELECTED",
            "next_arm": defaults.string(forKey: nextKey) ?? Arm.baseline8.rawValue,
            "effective_next_arm": next,
            "preferred_16_enabled": preferred,
            "preferred_16_eligible": eligible,
            "restart_required": next != (selected?.rawValue ?? Arm.baseline8.rawValue),
            "pending": defaults.bool(forKey: pendingKey),
            "confirmed_candidate16": defaults.bool(forKey: confirmedKey),
            "confirmed_candidate24": defaults.bool(forKey: candidate24CompletedKey),
            "confirmed_candidate32": defaults.bool(forKey: candidate32CompletedKey),
            "candidate32_consent_logged": defaults.bool(forKey: higherRiskConsentKey),
            "experiment_sweep": "Build102_32K_one_shot",
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
