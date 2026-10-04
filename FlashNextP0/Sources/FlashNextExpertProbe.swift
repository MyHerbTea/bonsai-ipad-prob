import Foundation
import MLX

enum FlashNextProbeError: LocalizedError {
    case noSwitchMLPWeight
    case missingCompanion(String)
    case unsupportedShape(String)
    case invalidInputDimension(Int)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .noSwitchMLPWeight:
            return "No quantized switch_mlp weight with matching scales/biases was found in this shard."
        case .missingCompanion(let key):
            return "Missing companion tensor: \(key)"
        case .unsupportedShape(let message):
            return "Unsupported tensor shape: \(message)"
        case .invalidInputDimension(let value):
            return "Invalid inferred input dimension: \(value)"
        case .emptyOutput:
            return "Quantized projection returned an empty output."
        }
    }
}

struct FlashNextExpertProbe {
    static let bits = 3
    static let groupSize = 64
    static let cacheLimitBytes = 32 * 1_048_576

    static func run(shardURL: URL) throws -> String {
        let scoped = shardURL.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                shardURL.stopAccessingSecurityScopedResource()
            }
        }

        Memory.cacheLimit = cacheLimitBytes
        Memory.clearCache()
        Memory.peakMemory = 0

        let systemBefore = FlashNextReadSystemProbe()
        let mlxBefore = Memory.snapshot()
        let loadStart = Date()

        // P0-A intentionally loads this single shard on the CPU stream.
        // Only one selected expert slice participates in GPU evaluation.
        let arrays = try loadArrays(url: shardURL, stream: .cpu)
        let loadMs = Date().timeIntervalSince(loadStart) * 1_000

        let weightKey = try chooseExpertWeightKey(arrays)
        let base = String(weightKey.dropLast(".weight".count))
        let scalesKey = base + ".scales"
        let biasesKey = base + ".biases"

        guard let weight3D = arrays[weightKey] else {
            throw FlashNextProbeError.missingCompanion(weightKey)
        }
        guard let scales3D = arrays[scalesKey] else {
            throw FlashNextProbeError.missingCompanion(scalesKey)
        }
        guard let biases3D = arrays[biasesKey] else {
            throw FlashNextProbeError.missingCompanion(biasesKey)
        }

        guard weight3D.ndim == 3 else {
            throw FlashNextProbeError.unsupportedShape(
                "\(weightKey) expected rank 3, got \(weight3D.shape)"
            )
        }
        guard scales3D.ndim == 3, biases3D.ndim == 3 else {
            throw FlashNextProbeError.unsupportedShape(
                "scales/biases must be rank 3; scales=\(scales3D.shape) biases=\(biases3D.shape)"
            )
        }
        guard weight3D.dim(0) > 0 else {
            throw FlashNextProbeError.unsupportedShape("expert axis is empty")
        }

        // A single real expert answers the first gate:
        // can MLX Swift + M5 Metal execute Niwaki's packed 3-bit affine
        // projection without expanding the whole routed-expert tensor?
        let expertIndex = 0
        let weight = weight3D[expertIndex]
        let scales = scales3D[expertIndex]
        let biases = biases3D[expertIndex]

        guard weight.ndim == 2, scales.ndim == 2, biases.ndim == 2 else {
            throw FlashNextProbeError.unsupportedShape(
                "expert slices must be rank 2; weight=\(weight.shape) scales=\(scales.shape) biases=\(biases.shape)"
            )
        }

        // Packed affine weights use UInt32 storage. This is the same logical
        // width relationship used by MLX QuantizedLinear.
        let inputDims = weight.dim(-1) * 32 / bits
        guard inputDims > 0, inputDims.isMultiple(of: groupSize) else {
            throw FlashNextProbeError.invalidInputDimension(inputDims)
        }

        let input =
            (MLXArray(0 ..< inputDims).asType(.float32) / Float(max(inputDims, 1)))
            .reshaped([1, inputDims])
            .asType(.bfloat16)

        let systemBeforeEval = FlashNextReadSystemProbe()
        let mlxBeforeEval = Memory.snapshot()
        let evalStart = Date()

        let output = quantizedMM(
            input,
            weight,
            scales: scales,
            biases: biases,
            transpose: true,
            groupSize: groupSize,
            bits: bits,
            mode: .affine
        ).asType(.float32)

        eval(output)

        let evalMs = Date().timeIntervalSince(evalStart) * 1_000
        let values = output.asArray(Float.self)
        guard !values.isEmpty else {
            throw FlashNextProbeError.emptyOutput
        }

        var finiteCount = 0
        var nanCount = 0
        var infCount = 0
        var sum: Double = 0
        var minValue = Float.greatestFiniteMagnitude
        var maxValue = -Float.greatestFiniteMagnitude
        var checksum: UInt64 = 1_469_598_103_934_665_603

        for value in values {
            if value.isNaN {
                nanCount += 1
            } else if !value.isFinite {
                infCount += 1
            } else {
                finiteCount += 1
                sum += Double(value)
                minValue = min(minValue, value)
                maxValue = max(maxValue, value)
            }

            checksum ^= UInt64(value.bitPattern)
            checksum &*= 1_099_511_628_211
        }

        let mean = finiteCount > 0 ? sum / Double(finiteCount) : .nan
        let mlxAfter = Memory.snapshot()
        let systemAfter = FlashNextReadSystemProbe()

        let candidateKeys = expertCandidateKeys(arrays)
        let result = (nanCount == 0 && infCount == 0) ? "PASS" : "FAIL"

        return """
        === FLASHNEXT IPAD PROBE ===
        phase=P0-A
        probe_version=0.1
        model_family=Qwen3.8-Flash-Next / Niwaki v2.4
        mlx_swift=0.32.3
        asset=\(shardURL.lastPathComponent)

        tensor=\(weightKey)
        candidate_projection_count=\(candidateKeys.count)
        expert_index=\(expertIndex)
        packed_weight_shape=\(weight.shape)
        scales_shape=\(scales.shape)
        biases_shape=\(biases.shape)
        logical_input_dims=\(inputDims)
        output_shape=\(output.shape)
        quant_bits=\(bits)
        group_size=\(groupSize)
        quant_mode=affine

        load_ms=\(format(loadMs))
        eval_ms=\(format(evalMs))

        mlx_before_active_mib=\(mib(mlxBefore.activeMemory))
        mlx_before_cache_mib=\(mib(mlxBefore.cacheMemory))
        mlx_before_eval_active_mib=\(mib(mlxBeforeEval.activeMemory))
        mlx_before_eval_cache_mib=\(mib(mlxBeforeEval.cacheMemory))
        mlx_after_active_mib=\(mib(mlxAfter.activeMemory))
        mlx_after_cache_mib=\(mib(mlxAfter.cacheMemory))
        mlx_peak_mib=\(mib(mlxAfter.peakMemory))

        available_before_mib=\(mib(systemBefore.available_bytes))
        footprint_before_mib=\(mib(systemBefore.phys_footprint_bytes))
        available_before_eval_mib=\(mib(systemBeforeEval.available_bytes))
        footprint_before_eval_mib=\(mib(systemBeforeEval.phys_footprint_bytes))
        available_after_mib=\(mib(systemAfter.available_bytes))
        footprint_after_mib=\(mib(systemAfter.phys_footprint_bytes))

        output_count=\(values.count)
        output_checksum_fnv1a64=\(String(format: "%016llx", checksum))
        output_min=\(format(Double(minValue)))
        output_max=\(format(Double(maxValue)))
        output_mean=\(format(mean))
        nan_count=\(nanCount)
        inf_count=\(infCount)

        result=\(result)
        """
    }

    private static func expertCandidateKeys(_ arrays: [String: MLXArray]) -> [String] {
        arrays.keys
            .filter { key in
                guard key.contains(".switch_mlp."), key.hasSuffix(".weight") else {
                    return false
                }
                let base = String(key.dropLast(".weight".count))
                return arrays[base + ".scales"] != nil && arrays[base + ".biases"] != nil
            }
            .sorted()
    }

    private static func chooseExpertWeightKey(_ arrays: [String: MLXArray]) throws -> String {
        let candidates = expertCandidateKeys(arrays)

        if let gate = candidates.first(where: { $0.contains(".gate_proj.") }) {
            return gate
        }
        if let up = candidates.first(where: { $0.contains(".up_proj.") }) {
            return up
        }
        if let down = candidates.first(where: { $0.contains(".down_proj.") }) {
            return down
        }
        guard let first = candidates.first else {
            throw FlashNextProbeError.noSwitchMLPWeight
        }
        return first
    }

    private static func mib<T: BinaryInteger>(_ bytes: T) -> String {
        String(format: "%.1f", Double(Int64(bytes)) / 1_048_576.0)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}
