import Foundation

@main
struct Build100Batch16GuardTests {
    static func main() {
        let id = "Build100B16Policy-" + UUID().uuidString
        let d = UserDefaults(suiteName: id)!
        defer { d.removePersistentDomain(forName: id) }
        func reset() {
            d.removePersistentDomain(forName: id)
            Build94BatchExperiment.resetForTests()
        }
        func launch() -> Build94BatchExperiment.Arm? {
            Build94BatchExperiment.resetForTests()
            return Build94BatchExperiment.select(context: 32_768, defaults: d)
        }

        reset()
        assert(launch() == .baseline8, "No certification: do not auto-enable B16")
        assert(!d.bool(forKey: Build94BatchExperiment.preferB16Key))
        Build94BatchExperiment.noteTextSuccess(promptTokens: 220, defaults: d)
        assert(d.bool(forKey: Build94BatchExperiment.baselineOKKey))
        assert(Build94BatchExperiment.scheduleNext(.candidate16, acknowledgeRecovery: false, defaults: d))
        assert(launch() == .candidate16, "One-shot original Build94 candidate")
        assert(d.bool(forKey: Build94BatchExperiment.pendingKey))
        Build94BatchExperiment.noteTextSuccess(promptTokens: 300, defaults: d)
        assert(d.bool(forKey: Build94BatchExperiment.confirmedKey))
        assert(!d.bool(forKey: Build94BatchExperiment.pendingKey))
        print("PASS: Build94 B8 then B16 qualification still required")

        d.set(true, forKey: Build94BatchExperiment.preferB16Key)
        assert(launch() == .candidate16, "Explicit B16 opt-in and qualification")
        assert(d.bool(forKey: Build94BatchExperiment.pendingKey))
        assert(Build94BatchExperiment.snapshot(defaults: d)["effective_next_arm"] as? String == "CANDIDATE16")
        Build94BatchExperiment.noteTextSuccess(promptTokens: 300, defaults: d)
        assert(launch() == .candidate16, "Repeat B16 only after previous substantial success")
        assert(d.bool(forKey: Build94BatchExperiment.pendingKey))
        print("PASS: opt-in repeated B16 remains guarded and process-scoped")

        // Simulate crash/premature exit without 200 input tokens.
        assert(launch() == .safe4, "Incomplete trial must force safe4")
        assert(d.bool(forKey: Build94BatchExperiment.fallbackKey))
        assert(!d.bool(forKey: Build94BatchExperiment.preferB16Key))
        assert(!Build94BatchExperiment.scheduleNext(.candidate16, acknowledgeRecovery: false, defaults: d))
        assert(Build94BatchExperiment.scheduleNext(.baseline8, acknowledgeRecovery: true, defaults: d))
        assert(launch() == .baseline8, "Explicit acknowledgement recovers only baseline8")
        print("PASS: abnormal candidate exit -> sticky safe4, no auto rearm")

        reset()
        d.set(true, forKey: Build94BatchExperiment.preferB16Key)
        assert(launch() == .baseline8, "B16 preference cannot bypass baseline/candidate certification")
        assert(!d.bool(forKey: Build94BatchExperiment.preferB16Key))
        print("PASS: uncertified preference is rejected without allocating 16/16")

        reset()
        d.set(true, forKey: Build94BatchExperiment.preferB16Key)
        d.set(true, forKey: Build94BatchExperiment.confirmedKey)
        d.set(true, forKey: Build94BatchExperiment.baselineOKKey)
        d.set(true, forKey: Build93BatchTrialPolicy.fallbackKey)
        assert(launch() == .safe4, "Inherited Build93 failure wins")
        assert(!d.bool(forKey: Build94BatchExperiment.preferB16Key))
        print("PASS: inherited fallback cannot be bypassed")

        reset()
        d.set(true, forKey: Build94BatchExperiment.confirmedKey)
        d.set(true, forKey: Build94BatchExperiment.baselineOKKey)
        d.set(true, forKey: Build94BatchExperiment.preferB16Key)
        assert(launch() == .candidate16)
        Build94BatchExperiment.noteStartupFailure(defaults: d)
        assert(!d.bool(forKey: Build94BatchExperiment.preferB16Key))
        assert(launch() == .safe4, "startup failure -> safe4")
        print("PASS: init failure disables B16 preference and forces safe4")

        reset()
        d.set(true, forKey: Build94BatchExperiment.confirmedKey)
        d.set(true, forKey: Build94BatchExperiment.baselineOKKey)
        d.set(true, forKey: Build94BatchExperiment.preferB16Key)
        assert(launch() == .candidate16)
        Build94BatchExperiment.noteTextSuccess(promptTokens: 220, defaults: d)
        assert(Build94BatchExperiment.scheduleNext(.baseline8, acknowledgeRecovery: false, defaults: d))
        assert(!d.bool(forKey: Build94BatchExperiment.preferB16Key))
        assert(launch() == .baseline8)
        assert(Build94BatchExperiment.select(context: 16_384, defaults: d) == nil)
        print("PASS: explicit B8 exit path and non-32K isolation")
    }
}
