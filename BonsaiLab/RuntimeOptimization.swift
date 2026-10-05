import Foundation

enum RuntimeOptimizationProfile: String, Codable, CaseIterable, Sendable {
    case baseline = "BASELINE"
    case experimental = "EXPERIMENTAL"
    case accelerated = "ACCELERATED"
}

struct RuntimeFeatureFlags: Codable, Equatable, Sendable {
    var extendedTelemetry = true
    var metalAwareGovernor = false
    var heapPressureRelief = false
    var metalTensorPrefill = false
    var metalFusionExperimental = false
    var lazyEmbedding = false
    var prefixStateCache = false
    var tieredKV = false
    var tieredKVQuantizedCold = false
    var aneColdKV = false
    var speculativeExperimental = false

    static let baseline = RuntimeFeatureFlags()

    var wireDictionary: [String: Bool] {
        [
            "bb.telemetry.extended": extendedTelemetry,
            "bb.governor.metalAware": metalAwareGovernor,
            "bb.heapPressureRelief": heapPressureRelief,
            "bb.metalTensor.prefill": metalTensorPrefill,
            "bb.metalFusion.experimental": metalFusionExperimental,
            "bb.lazyEmbedding": lazyEmbedding,
            "bb.prefixStateCache": prefixStateCache,
            "bb.tieredKV": tieredKV,
            "bb.tieredKV.quantizedCold": tieredKVQuantizedCold,
            "bb.aneColdKV": aneColdKV,
            "bb.speculative.experimental": speculativeExperimental
        ]
    }

    static func fromWireDictionary(
        _ values: [String: Any]
    ) -> RuntimeFeatureFlags {
        var flags = RuntimeFeatureFlags.baseline

        func bool(_ key: String, fallback: Bool) -> Bool {
            if let value = values[key] as? Bool {
                return value
            }
            if let number = values[key] as? NSNumber {
                return number.boolValue
            }
            return fallback
        }

        flags.extendedTelemetry = bool(
            "bb.telemetry.extended",
            fallback: true
        )
        flags.metalAwareGovernor = bool(
            "bb.governor.metalAware",
            fallback: false
        )
        flags.heapPressureRelief = bool(
            "bb.heapPressureRelief",
            fallback: false
        )
        flags.metalTensorPrefill = bool(
            "bb.metalTensor.prefill",
            fallback: false
        )
        flags.metalFusionExperimental = bool(
            "bb.metalFusion.experimental",
            fallback: false
        )
        flags.lazyEmbedding = bool(
            "bb.lazyEmbedding",
            fallback: false
        )
        flags.prefixStateCache = bool(
            "bb.prefixStateCache",
            fallback: false
        )
        flags.tieredKV = bool(
            "bb.tieredKV",
            fallback: false
        )
        flags.tieredKVQuantizedCold = bool(
            "bb.tieredKV.quantizedCold",
            fallback: false
        )
        flags.aneColdKV = bool(
            "bb.aneColdKV",
            fallback: false
        )
        flags.speculativeExperimental = bool(
            "bb.speculative.experimental",
            fallback: false
        )

        return flags
    }

    var enabledBehaviorChangingWireKeys: [String] {
        wireDictionary
            .filter { key, value in
                key != "bb.telemetry.extended" && value
            }
            .map(\.key)
            .sorted()
    }

    var hasBehaviorChangingFeature: Bool {
        metalAwareGovernor
            || heapPressureRelief
            || metalTensorPrefill
            || metalFusionExperimental
            || lazyEmbedding
            || prefixStateCache
            || tieredKV
            || tieredKVQuantizedCold
            || aneColdKV
            || speculativeExperimental
    }
}

struct RuntimeOptimizationState: Codable, Equatable, Sendable {
    var profile: RuntimeOptimizationProfile = .baseline
    var requested: RuntimeFeatureFlags = .baseline
    var effective: RuntimeFeatureFlags = .baseline
    var fallbacks: [String] = []

    static let baseline = RuntimeOptimizationState()

    var isValidBaseline: Bool {
        profile != .baseline || !effective.hasBehaviorChangingFeature
    }
}

struct RuntimeTelemetrySnapshot: Codable, Equatable, Sendable {
    let capturedAt: Date
    let stage: String
    let availableBytes: UInt64
    let residentBytes: UInt64
    let virtualBytes: UInt64
    let physFootprintBytes: UInt64
    let metalAllocatedBytes: UInt64
    let metalRecommendedWorkingSetBytes: UInt64
    let metalHeadroomBytes: UInt64
    let hasUnifiedMemory: Bool
    let thermalState: String

    static func capture(stage: String) -> RuntimeTelemetrySnapshot {
        let probe = BonsaiReadSystemProbe()
        let recommended = UInt64(probe.metal_recommended_bytes)
        let allocated = UInt64(probe.metal_allocated_bytes)
        let headroom = recommended > allocated
            ? recommended - allocated
            : 0

        return RuntimeTelemetrySnapshot(
            capturedAt: Date(),
            stage: stage,
            availableBytes: UInt64(probe.available_bytes),
            residentBytes: UInt64(probe.resident_bytes),
            virtualBytes: UInt64(probe.virtual_bytes),
            physFootprintBytes: UInt64(probe.phys_footprint_bytes),
            metalAllocatedBytes: allocated,
            metalRecommendedWorkingSetBytes: recommended,
            metalHeadroomBytes: headroom,
            hasUnifiedMemory: probe.has_unified_memory != 0,
            thermalState: Self.thermalStateName(
                ProcessInfo.processInfo.thermalState
            )
        )
    }

    private static func thermalStateName(
        _ value: ProcessInfo.ThermalState
    ) -> String {
        switch value {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}

struct RuntimeBenchmarkProvenance: Codable, Equatable, Sendable {
    let runID: String
    let fixtureID: String
    let commitSHA: String
    let modelSHA256: String?
    let promptSHA256: String
    let imageSHA256: String?
    let profile: RuntimeOptimizationProfile
    let requestedFlags: RuntimeFeatureFlags
    let effectiveFlags: RuntimeFeatureFlags
    let fallbacks: [String]
}
