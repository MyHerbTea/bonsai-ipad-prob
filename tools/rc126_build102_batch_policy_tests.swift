import Foundation

/// Device-independent launch policy tests. Native 24/32 evaluation is separately
/// gated by real iPad tests; this suite must not silently imply performance success.
@main
struct Build102BatchSweepPolicyTests {
    static func main() {
        let suite = "Build102BatchSweep-" + UUID().uuidString
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        func fresh() {
            d.removePersistentDomain(forName: suite)
            Build94BatchExperiment.resetForTests()
        }
        func launch() -> Build94BatchExperiment.Arm? {
            Build94BatchExperiment.resetForTests()
            return Build94BatchExperiment.select(context: 32_768, defaults: d)
        }
        fresh()
        assert(launch() == .baseline8)
        assert(!Build94BatchExperiment.scheduleNext(.candidate24, acknowledgeRecovery: false, defaults: d))
        assert(!Build94BatchExperiment.scheduleNext(.candidate32, acknowledgeRecovery: false, acknowledgeHigherRisk: true, defaults: d))
        Build94BatchExperiment.noteTextSuccess(promptTokens: 939, defaults: d)
        assert(Build94BatchExperiment.scheduleNext(.candidate16, acknowledgeRecovery: false, defaults: d))
        assert(launch() == .candidate16)
        Build94BatchExperiment.noteTextSuccess(promptTokens: 939, defaults: d)
        assert(d.bool(forKey: Build94BatchExperiment.confirmedKey))
        print("PASS: B24 gated by prior successful B16 and B8")

        assert(Build94BatchExperiment.scheduleNext(.candidate24, acknowledgeRecovery: false, defaults: d))
        let prepared = Build94BatchExperiment.snapshot(defaults: d)
        assert(prepared["next_arm"] as? String == "CANDIDATE24")
        assert(launch() == .candidate24)
        assert(d.bool(forKey: Build94BatchExperiment.pendingKey))
        assert(!d.bool(forKey: Build94BatchExperiment.candidate24CompletedKey))
        assert(d.string(forKey: Build94BatchExperiment.nextKey) == "BASELINE8")
        Build94BatchExperiment.noteTextSuccess(promptTokens: 128, defaults: d)
        assert(d.bool(forKey: Build94BatchExperiment.pendingKey))
        Build94BatchExperiment.noteTextSuccess(promptTokens: 939, defaults: d)
        assert(!d.bool(forKey: Build94BatchExperiment.pendingKey))
        assert(d.bool(forKey: Build94BatchExperiment.candidate24CompletedKey))
        assert(launch() == .baseline8)
        print("PASS: one-shot B24 requires >=200 prompt, reverts to B8 without auto-promotion")

        assert(Build94BatchExperiment.scheduleNext(.candidate16, acknowledgeRecovery: false, defaults: d))
        assert(launch() == .candidate16)
        Build94BatchExperiment.noteTextSuccess(promptTokens: 939, defaults: d)
        assert(launch() == .baseline8)
        assert(!Build94BatchExperiment.scheduleNext(.candidate32, acknowledgeRecovery: false, defaults: d))
        assert(!Build94BatchExperiment.scheduleNext(.candidate32, acknowledgeRecovery: false, acknowledgeHigherRisk: false, defaults: d))
        assert(Build94BatchExperiment.scheduleNext(.candidate32, acknowledgeRecovery: false, acknowledgeHigherRisk: true, defaults: d))
        assert(d.bool(forKey: Build94BatchExperiment.higherRiskConsentKey))
        assert(launch() == .candidate32)
        assert(d.bool(forKey: Build94BatchExperiment.pendingKey))
        Build94BatchExperiment.noteStartupFailure(defaults: d)
        assert(!d.bool(forKey: Build94BatchExperiment.pendingKey))
        assert(d.bool(forKey: Build94BatchExperiment.fallbackKey))
        assert(launch() == .safe4)
        assert(!Build94BatchExperiment.scheduleNext(.candidate16, acknowledgeRecovery: false, defaults: d))
        assert(!Build94BatchExperiment.scheduleNext(.candidate24, acknowledgeRecovery: false, defaults: d))
        assert(!Build94BatchExperiment.scheduleNext(.candidate32, acknowledgeRecovery: false, acknowledgeHigherRisk: true, defaults: d))
        assert(Build94BatchExperiment.scheduleNext(.baseline8, acknowledgeRecovery: true, defaults: d))
        assert(launch() == .baseline8)
        print("PASS: B32 requires explicit consent; startup failure locks SAFE4 until recovery ack")

        fresh()
        d.set(true, forKey: Build94BatchExperiment.baselineOKKey)
        d.set(true, forKey: Build94BatchExperiment.confirmedKey)
        d.set(true, forKey: Build94BatchExperiment.preferB16Key)
        assert(Build94BatchExperiment.scheduleNext(.candidate24, acknowledgeRecovery: false, defaults: d))
        assert(!d.bool(forKey: Build94BatchExperiment.preferB16Key))
        assert(launch() == .candidate24)
        assert(launch() == .safe4, "incomplete B24 process must not re-enter accelerator")
        assert(d.bool(forKey: Build94BatchExperiment.fallbackKey))
        print("PASS: Build100 auto-B16 preference cannot override a scheduled B24, crash -> SAFE4")

        fresh()
        assert(Build94BatchExperiment.select(context: 16_384, defaults: d) == nil)
        assert(Build94BatchExperiment.select(context: 65_536, defaults: d) == nil)
        print("PASS: contexts other than exact 32K retain existing policy")
    }
}
