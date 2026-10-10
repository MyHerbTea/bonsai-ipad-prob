import Foundation
@main
struct Build104IntegratedPolicy {
    static func main() {
        let suite = "Build104-" + UUID().uuidString
        let d = UserDefaults(suiteName:suite)!
        defer { d.removePersistentDomain(forName:suite) }
        func fresh() {
            d.removePersistentDomain(forName:suite)
            Build94BatchExperiment.resetForTests()
        }
        func launch() -> Build94BatchExperiment.Arm? {
            Build94BatchExperiment.resetForTests()
            return Build94BatchExperiment.select(context:32768, defaults:d)
        }
        fresh()
        assert(launch() == .baseline8)
        Build94BatchExperiment.noteTextSuccess(promptTokens:400,defaults:d)
        assert(Build94BatchExperiment.scheduleNext(.candidate16,acknowledgeRecovery:false,defaults:d))
        assert(launch() == .candidate16)
        Build94BatchExperiment.noteTextSuccess(promptTokens:400,defaults:d)
        assert(Build94BatchExperiment.scheduleNext(.candidate24,acknowledgeRecovery:false,defaults:d))
        assert(launch() == .candidate24)
        Build94BatchExperiment.noteTextSuccess(promptTokens:400,defaults:d)
        assert(launch() == .baseline8)
        d.set(true,forKey:Build94BatchExperiment.preferB24Key)
        assert(launch() == .candidate24)
        Build94BatchExperiment.noteTextSuccess(promptTokens:400,defaults:d)
        assert(launch() == .candidate24)
        Build94BatchExperiment.noteTextSuccess(promptTokens:400,defaults:d)
        d.set(false,forKey:Build94BatchExperiment.preferB24Key)
        assert(launch() == .baseline8)
        print("PASS: B24 persistence requires local qualification and opt-in; opt-out B8")

        fresh()
        d.set(true,forKey:Build94BatchExperiment.baselineOKKey)
        d.set(true,forKey:Build94BatchExperiment.confirmedKey)
        d.set(true,forKey:Build94BatchExperiment.candidate24CompletedKey)
        d.set(true,forKey:Build94BatchExperiment.preferB24Key)
        assert(launch() == .candidate24)
        assert(launch() == .safe4)
        assert(!d.bool(forKey:Build94BatchExperiment.preferB24Key))
        print("PASS: B24 interrupted startup => sticky SAFE4")

        fresh()
        d.set(true,forKey:Build94BatchExperiment.baselineOKKey)
        d.set(true,forKey:Build94BatchExperiment.confirmedKey)
        d.set(true,forKey:Build94BatchExperiment.candidate24CompletedKey)
        d.set(true,forKey:Build94BatchExperiment.preferB24Key)
        d.set(true,forKey:Build94BatchExperiment.preferB16Key)
        assert(launch() == .candidate16)
        Build94BatchExperiment.noteStartupFailure(defaults:d)
        assert(launch() == .safe4)
        print("PASS: manual B16 precedence and startup failure recovery")
    }
}
