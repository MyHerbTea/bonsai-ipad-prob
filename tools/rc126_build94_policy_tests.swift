import Foundation
@main
struct Build94ABPolicyTests {
    static func main() {
        let suite = "BonsaiBuild94-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func reset() {
            defaults.removePersistentDomain(forName: suite)
            Build94BatchExperiment.resetForTests()
        }

        reset()
        assert(Build94BatchExperiment.select(context: 16_384, defaults: defaults) == nil)
        assert(Build94BatchExperiment.select(context: 65_536, defaults: defaults) == nil)
        assert(Build94BatchExperiment.select(context: 32_768, defaults: defaults) == .baseline8)
        assert(!Build94BatchExperiment.scheduleNext(.candidate16, acknowledgeRecovery: false, defaults: defaults))
        Build94BatchExperiment.noteTextSuccess(promptTokens: 220, defaults: defaults)
        assert(defaults.bool(forKey: Build94BatchExperiment.baselineOKKey))
        assert(Build94BatchExperiment.scheduleNext(.candidate16, acknowledgeRecovery: false, defaults: defaults))
        assert(Build94BatchExperiment.select(context: 32_768, defaults: defaults) == .baseline8)
        print("PASS: baseline8 must complete and next-arm never changes allocated context")

        Build94BatchExperiment.resetForTests()
        assert(Build94BatchExperiment.select(context: 32_768, defaults: defaults) == .candidate16)
        assert(defaults.bool(forKey: Build94BatchExperiment.pendingKey))
        assert(defaults.string(forKey: Build94BatchExperiment.nextKey) == "BASELINE8")
        Build94BatchExperiment.noteTextSuccess(promptTokens: 128, defaults: defaults)
        assert(defaults.bool(forKey: Build94BatchExperiment.pendingKey))
        Build94BatchExperiment.noteTextSuccess(promptTokens: 256, defaults: defaults)
        assert(!defaults.bool(forKey: Build94BatchExperiment.pendingKey))
        assert(defaults.bool(forKey: Build94BatchExperiment.confirmedKey))
        print("PASS: candidate16 trial consumes one-shot arm and clears marker only after success")

        reset()
        defaults.set("CANDIDATE16", forKey: Build94BatchExperiment.nextKey)
        assert(Build94BatchExperiment.select(context: 32_768, defaults: defaults) == .candidate16)
        Build94BatchExperiment.resetForTests()
        assert(Build94BatchExperiment.select(context: 32_768, defaults: defaults) == .safe4)
        assert(defaults.bool(forKey: Build94BatchExperiment.fallbackKey))
        assert(!Build94BatchExperiment.scheduleNext(.candidate16, acknowledgeRecovery: false, defaults: defaults))
        assert(!Build94BatchExperiment.scheduleNext(.baseline8, acknowledgeRecovery: false, defaults: defaults))
        assert(Build94BatchExperiment.scheduleNext(.baseline8, acknowledgeRecovery: true, defaults: defaults))
        print("PASS: incomplete trial -> sticky safe4; rearm requires explicit recovery acknowledgement")

        reset()
        defaults.set(true, forKey: Build93BatchTrialPolicy.fallbackKey)
        assert(Build94BatchExperiment.select(context: 32_768, defaults: defaults) == .safe4)
        print("PASS: inherited Build93 sticky fallback remains respected")

        reset()
        defaults.set("CANDIDATE16", forKey: Build94BatchExperiment.nextKey)
        assert(Build94BatchExperiment.select(context: 32_768, defaults: defaults) == .candidate16)
        Build94BatchExperiment.noteStartupFailure(defaults: defaults)
        assert(defaults.bool(forKey: Build94BatchExperiment.fallbackKey))
        assert(!defaults.bool(forKey: Build94BatchExperiment.pendingKey))
        Build94BatchExperiment.resetForTests()
        assert(Build94BatchExperiment.select(context: 32_768, defaults: defaults) == .safe4)
        print("PASS: startup exception -> safe4 on next authorized start")
    }
}
