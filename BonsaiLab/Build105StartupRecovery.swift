import Foundation

/// One-time Build104 -> Build105 crash-loop recovery.
///
/// Only risky experimental preferences are invalidated. Preserve the existing
/// sticky SAFE4 decision when an experimental launch was interrupted.
/// No model selection, context, API key, or output configuration is touched.
enum Build105StartupRecovery {
    static let migrationKey = "BonsaiBuild105RecoveryMigrationComplete"

    static func apply(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: migrationKey) else { return }
        defaults.set(false, forKey: Build94BatchExperiment.preferB24Key)
        defaults.set(false, forKey: Build94BatchExperiment.preferB16Key)
        defaults.set(false, forKey: "BonsaiBuild104TextKVCheckpointEnabled")

        if defaults.bool(forKey: Build94BatchExperiment.pendingKey) {
            defaults.set(true, forKey: Build94BatchExperiment.fallbackKey)
            defaults.set(false, forKey: Build94BatchExperiment.pendingKey)
            defaults.set(
                "build104_interrupted_safe4",
                forKey: Build94BatchExperiment.reasonKey
            )
        } else if !defaults.bool(forKey: Build94BatchExperiment.fallbackKey) &&
                    !defaults.bool(forKey: Build93BatchTrialPolicy.fallbackKey) {
            defaults.set(
                Build94BatchExperiment.Arm.baseline8.rawValue,
                forKey: Build94BatchExperiment.nextKey
            )
        }

        defaults.set(true, forKey: migrationKey)
        defaults.synchronize()
    }
}
