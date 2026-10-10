import Foundation

/// Build99 speed lab: opt-in, one-process append-only text-state experiment.
///
/// The candidate is consumed on the next full app launch and immediately
/// resets to OFF. Neither LAN API nor in-flight requests can change the arm.
enum Build99AppendOnlyReuse {
    static let nextKey = "BonsaiBuild99AppendOnlyNextArm"
    static let activeKey = "BonsaiBuild99AppendOnlyActiveArm"
    static let residentTokensKey = "BonsaiBuild99AppendOnlyResidentTokens"

    static let activeArm: String = {
        let defaults = UserDefaults.standard
        let next = defaults.string(forKey: nextKey) ?? "OFF"
        let arm = next == "APPEND" ? "APPEND" : "OFF"
        defaults.set("OFF", forKey: nextKey)
        defaults.set(arm, forKey: activeKey)
        defaults.set(0, forKey: residentTokensKey)
        defaults.synchronize()
        return arm
    }()

    static var enabled: Bool { activeArm == "APPEND" }

    static func snapshot() -> [String: Any] {
        let defaults = UserDefaults.standard
        return [
            "schema": "bonsai-build99-append-only-v1",
            "active_arm": activeArm,
            "next_launch_arm": defaults.string(forKey: nextKey) ?? "OFF",
            "auto_revert_next_launch": true,
            "resident_token_count": defaults.integer(forKey: residentTokensKey),
            "requires_full_app_relaunch": true
        ]
    }
}
