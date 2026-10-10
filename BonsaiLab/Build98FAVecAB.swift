import Foundation
import Darwin

/// Isolated one-process M5 FA-vec experiment. No API request can select an arm.
/// UI schedules next process launch; every candidate automatically resets to A0
/// on the following process launch, including after an unexpected termination.
enum Build98FAVecAB {
    static let nextKey = "BonsaiBuild98FAVecNextArm"
    static let activeKey = "BonsaiBuild98FAVecActiveArm"

    static func installAtProcessLaunch() {
        let defaults = UserDefaults.standard
        let requested = defaults.string(forKey: nextKey) ?? "A0"
        let effective = ["A0", "A1", "A2"].contains(requested) ? requested : "A0"
        // Always revert next launch to A0. An incomplete candidate cannot
        // become a permanent default following a crash or forced termination.
        defaults.set("A0", forKey: nextKey)
        defaults.set(effective, forKey: activeKey)

        let path = tracePath
        try? FileManager.default.removeItem(atPath: path)
        setenv("BONSAI_FA_VEC_ARM", effective, 1)
        setenv("BONSAI_FA_VEC_TRACE_PATH", path, 1)
        defaults.synchronize()
    }

    static var tracePath: String {
        (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("bonsai_build98_fa_vec_decision.txt")
    }

    static func snapshot() -> [String: Any] {
        let defaults = UserDefaults.standard
        let active = defaults.string(forKey: activeKey) ?? "A0"
        let next = defaults.string(forKey: nextKey) ?? "A0"
        let raw = (try? String(contentsOfFile: tracePath, encoding: .utf8)) ?? ""
        var native: [String: String] = [:]
        for line in raw.split(separator: "\n") {
            guard let separator = line.firstIndex(of: "=") else { continue }
            native[String(line[..<separator])] = String(line[line.index(after: separator)...])
        }
        return [
            "schema": "bonsai-build98-fa-vec-ab-v1",
            "active_arm": active,
            "next_launch_arm": next,
            "requires_process_restart": next != active,
            "auto_revert_next_launch": true,
            "native_matched": native["matched"] == "1",
            "native_decision": native,
            "trace_status": raw.isEmpty ? "not_yet_observed" : "recorded"
        ]
    }
}
