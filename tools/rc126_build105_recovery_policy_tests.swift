import Foundation

@main
struct Build105RecoveryDeviceIndependentTests {
    static func main() {
        let name = "Build105-" + UUID().uuidString
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }

        // Previously qualified B24 preference must not auto-arm the
        // 32K allocation immediately after upgrading a crashing Build104.
        d.set(true, forKey: Build94BatchExperiment.preferB24Key)
        d.set(true, forKey: Build94BatchExperiment.preferB16Key)
        d.set(true, forKey: "BonsaiBuild104TextKVCheckpointEnabled")
        d.set(true, forKey: Build94BatchExperiment.baselineOKKey)
        d.set(true, forKey: Build94BatchExperiment.confirmedKey)
        d.set(true, forKey: Build94BatchExperiment.candidate24CompletedKey)
        Build105StartupRecovery.apply(defaults: d)
        assert(!d.bool(forKey: Build94BatchExperiment.preferB24Key))
        assert(!d.bool(forKey: Build94BatchExperiment.preferB16Key))
        assert(!d.bool(forKey: "BonsaiBuild104TextKVCheckpointEnabled"))
        assert(d.string(forKey: Build94BatchExperiment.nextKey) == "BASELINE8")
        Build94BatchExperiment.resetForTests()
        assert(Build94BatchExperiment.select(context: 32768, defaults: d) == .baseline8)
        print("PASS: qualified B24 migration defaults to proven baseline8")

        d.removePersistentDomain(forName: name)
        Build94BatchExperiment.resetForTests()
        d.set(true, forKey: Build94BatchExperiment.pendingKey)
        d.set(true, forKey: Build94BatchExperiment.preferB24Key)
        Build105StartupRecovery.apply(defaults: d)
        assert(d.bool(forKey: Build94BatchExperiment.fallbackKey))
        assert(!d.bool(forKey: Build94BatchExperiment.pendingKey))
        assert(Build94BatchExperiment.select(context: 32768, defaults: d) == .safe4)
        print("PASS: interrupted experimental attempt preserves sticky SAFE4")

        d.removePersistentDomain(forName: name)
        Build94BatchExperiment.resetForTests()
        d.set(true, forKey: Build93BatchTrialPolicy.fallbackKey)
        d.set("CANDIDATE24", forKey: Build94BatchExperiment.nextKey)
        Build105StartupRecovery.apply(defaults: d)
        assert(Build94BatchExperiment.select(context: 32768, defaults: d) == .safe4)
        print("PASS: inherited Build93 safety fallback is never bypassed")

        let before = d.dictionaryRepresentation()
        Build105StartupRecovery.apply(defaults: d)
        let after = d.dictionaryRepresentation()
        assert(before.count == after.count)
        print("PASS: migration idempotent")
    }
}
