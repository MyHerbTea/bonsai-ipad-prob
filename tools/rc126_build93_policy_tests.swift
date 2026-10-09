import Foundation

@main
struct Build93PolicyTests {
    static func main() {
        let name = "BonsaiBuild93Policy-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        func reset() {
            defaults.removePersistentDomain(forName: name)
            Build93BatchTrialPolicy.resetProcessSelectionForTests()
        }

        reset()
        assert(Build93BatchTrialPolicy.select(context: 32_768, defaults: defaults) == .candidate8)
        assert(defaults.bool(forKey: Build93BatchTrialPolicy.pendingKey))
        assert(defaults.string(forKey: Build93BatchTrialPolicy.modeKey) == "candidate_8_8")
        assert(Build93BatchTrialPolicy.select(context: 32_768, defaults: defaults) == .candidate8)
        Build93BatchTrialPolicy.noteSuccessfulText(promptTokens: 256, defaults: defaults)
        assert(defaults.bool(forKey: Build93BatchTrialPolicy.pendingKey))
        Build93BatchTrialPolicy.noteSuccessfulText(promptTokens: 1024, defaults: defaults)
        assert(!defaults.bool(forKey: Build93BatchTrialPolicy.pendingKey))
        assert(defaults.bool(forKey: Build93BatchTrialPolicy.confirmedKey))
        print("PASS: candidate persists within process and validates after full >=1024-token text response")

        reset()
        defaults.set(true, forKey: Build93BatchTrialPolicy.pendingKey)
        assert(Build93BatchTrialPolicy.select(context: 32_768, defaults: defaults) == .fallback4)
        assert(defaults.bool(forKey: Build93BatchTrialPolicy.fallbackKey))
        assert(defaults.string(forKey: Build93BatchTrialPolicy.reasonKey) == "prior_candidate_attempt_incomplete")
        print("PASS: incomplete candidate attempt activates sticky 4/4 recovery")

        reset()
        assert(Build93BatchTrialPolicy.select(context: 32_768, defaults: defaults) == .candidate8)
        Build93BatchTrialPolicy.noteStartupFailure(defaults: defaults)
        assert(defaults.bool(forKey: Build93BatchTrialPolicy.fallbackKey))
        Build93BatchTrialPolicy.resetProcessSelectionForTests()
        assert(Build93BatchTrialPolicy.select(context: 32_768, defaults: defaults) == .fallback4)
        print("PASS: explicit startup failure activates next-run fallback")

        reset()
        assert(Build93BatchTrialPolicy.select(context: 16_384, defaults: defaults) == .notApplicable)
        assert(Build93BatchTrialPolicy.select(context: 65_536, defaults: defaults) == .notApplicable)
        assert(!defaults.bool(forKey: Build93BatchTrialPolicy.pendingKey))
        assert(Build93BatchTrialPolicy.select(context: 32_768, defaults: defaults) == .candidate8)
        print("PASS: other context policies untouched")
    }
}
