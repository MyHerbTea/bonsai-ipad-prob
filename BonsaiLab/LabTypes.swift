import Foundation

enum ModelLoadMode: String, CaseIterable, Identifiable, Sendable {
    case mmap = "MMAP"
    case none = "NONE"

    var id: String { rawValue }
}

struct RuntimeConfig: Equatable, Sendable {
    var context: Int = 256
    var batch: Int = 16
    var ubatch: Int = 16
    var gpuLayers: Int = 99
    var flashAttention: Bool = true
    var swaFull: Bool = false
    var offloadKQV: Bool = true
    var opOffload: Bool = true
    var disableMetalTensorAPI: Bool = true
    var kvUnified: Bool = false
    var loadMode: ModelLoadMode = .mmap

    static let safe = RuntimeConfig()

    static let textBalanced = RuntimeConfig(
        context: 1024,
        batch: 32,
        ubatch: 32,
        gpuLayers: 99,
        flashAttention: true,
        swaFull: false,
        offloadKQV: true,
        opOffload: true,
        disableMetalTensorAPI: true
    )

    static let visionSafe = RuntimeConfig(
        context: 512,
        batch: 16,
        ubatch: 16,
        gpuLayers: 99,
        flashAttention: true,
        swaFull: false,
        offloadKQV: true,
        opOffload: true,
        disableMetalTensorAPI: true,
        kvUnified: true
    )

    func validated() throws -> RuntimeConfig {
        guard context >= 256 && context <= 8192 else {
            throw LabError.invalidConfig("Context 必须在 256...8192。")
        }
        guard batch >= 1 && batch <= min(context, 512) else {
            throw LabError.invalidConfig("Batch 必须在 1...min(Context, 512)。")
        }
        guard ubatch >= 1 && ubatch <= batch else {
            throw LabError.invalidConfig("uBatch 必须在 1...Batch。")
        }
        guard gpuLayers >= 0 && gpuLayers <= 999 else {
            throw LabError.invalidConfig("GPU Layers 必须 >= 0。")
        }
        return self
    }

    var summary: String {
        "ctx=\(context), batch=\(batch), ubatch=\(ubatch), gpu=\(gpuLayers), FA=\(flashAttention ? "ON" : "OFF"), SWA=\(swaFull ? "ON" : "OFF"), KV_UNIFIED=\(kvUnified ? "ON" : "OFF"), LOAD=\(loadMode.rawValue)"
    }
}

struct GenerationConfig: Equatable, Sendable {
    var maxTokens: Int = 128
    var temperature: Double = 0.7
    var topP: Double = 0.8
    var topK: Int = 20
    var minP: Double = 0.0
    var repeatPenalty: Double = 1.0
    var seed: Int = 1234

    func validated(context: Int) throws -> GenerationConfig {
        guard maxTokens >= 1 && maxTokens <= max(1, context - 1) else {
            throw LabError.invalidConfig("Max Tokens 必须小于当前 Context。")
        }
        guard temperature >= 0 && temperature <= 5 else {
            throw LabError.invalidConfig("Temperature 必须在 0...5。")
        }
        guard topP > 0 && topP <= 1 else {
            throw LabError.invalidConfig("Top P 必须在 (0, 1]。")
        }
        guard topK >= 1 && topK <= 1000 else {
            throw LabError.invalidConfig("Top K 必须在 1...1000。")
        }
        guard minP >= 0 && minP <= 1 else {
            throw LabError.invalidConfig("Min P 必须在 0...1。")
        }
        guard repeatPenalty > 0 && repeatPenalty <= 3 else {
            throw LabError.invalidConfig("Repeat Penalty 必须在 (0, 3]。")
        }
        guard seed >= 0 else {
            throw LabError.invalidConfig("Seed 必须 >= 0。")
        }
        return self
    }
}

enum VisionPreset: String, CaseIterable, Identifiable, Sendable {
    case probe256
    case low512
    case mid768
    case full1024

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .probe256: return "256"
        case .low512: return "512"
        case .mid768: return "768"
        case .full1024: return "1024"
        }
    }

    var displayName: String {
        switch self {
        case .probe256: return "Probe 256"
        case .low512: return "Low 512"
        case .mid768: return "Mid 768"
        case .full1024: return "Full 1024"
        }
    }

    var config: VisionConfig {
        switch self {
        case .probe256: return .probe256
        case .low512: return .low512
        case .mid768: return .mid768
        case .full1024: return .full1024
        }
    }
}

enum VisionQuality: String, CaseIterable, Identifiable, Sendable {
    case fast
    case standard
    case detailed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fast: return "快速"
        case .standard: return "标准"
        case .detailed: return "详细"
        }
    }

    var preset: VisionPreset {
        switch self {
        case .fast: return .low512
        case .standard: return .mid768
        case .detailed: return .full1024
        }
    }

    var note: String {
        switch self {
        case .fast: return "更快，适合普通图片和简单问答"
        case .standard: return "速度与细节平衡，推荐默认"
        case .detailed: return "更多视觉细节，耗时更长"
        }
    }
}

enum AnswerLengthPreset: String, CaseIterable, Identifiable, Sendable {
    case short
    case standard
    case long

    var id: String { rawValue }

    var label: String {
        switch self {
        case .short: return "简短"
        case .standard: return "标准"
        case .long: return "详细"
        }
    }

    var maxTokens: Int {
        switch self {
        case .short: return 128
        case .standard: return 256
        case .long: return 384
        }
    }
}

enum VisionInferenceMode: String, CaseIterable, Identifiable, Sendable {
    case accelerated
    case safe

    var id: String { rawValue }

    var label: String {
        switch self {
        case .accelerated: return "加速"
        case .safe: return "安全"
        }
    }

    var detail: String {
        switch self {
        case .accelerated:
            return "Flash Attention ON · KQV/Op Offload ON"
        case .safe:
            return "Flash Attention OFF · KQV/Op Offload OFF"
        }
    }

    var bridgeValue: Int32 {
        switch self {
        case .accelerated: return 1
        case .safe: return 0
        }
    }
}

struct VisionConfig: Equatable, Sendable {
    // CPU projector is the mobile-safe default. The language model can remain on Metal.
    var useGPU: Bool = false
    // RC1.8 decouples image token budget from llama context size.
    var imageMaxTokens: Int = 128
    var warmup: Bool = false

    // Explicit llama vision-context controls.
    var contextTokens: Int = 512
    var contextBatch: Int = 8
    var contextUBatch: Int = 8
    var lowMemoryContext: Bool = true

    static let probe256 = VisionConfig(
        useGPU: false,
        imageMaxTokens: 64,
        warmup: false,
        contextTokens: 256,
        contextBatch: 4,
        contextUBatch: 4,
        lowMemoryContext: true
    )

    static let low512 = VisionConfig(
        useGPU: false,
        imageMaxTokens: 128,
        warmup: false,
        contextTokens: 512,
        contextBatch: 8,
        contextUBatch: 8,
        lowMemoryContext: true
    )

    static let mid768 = VisionConfig(
        useGPU: false,
        imageMaxTokens: 256,
        warmup: false,
        contextTokens: 768,
        contextBatch: 8,
        contextUBatch: 8,
        lowMemoryContext: true
    )

    static let full1024 = VisionConfig(
        useGPU: false,
        imageMaxTokens: 512,
        warmup: false,
        contextTokens: 1024,
        contextBatch: 16,
        contextUBatch: 16,
        lowMemoryContext: true
    )

    func validated() throws -> VisionConfig {
        guard imageMaxTokens >= 32 && imageMaxTokens <= 4096 else {
            throw LabError.invalidConfig("Image Max Tokens 必须在 32...4096。")
        }
        guard contextTokens >= 256 && contextTokens <= 4096 else {
            throw LabError.invalidConfig("Vision Context 必须在 256...4096。")
        }
        guard contextBatch >= 1 && contextBatch <= min(contextTokens, 128) else {
            throw LabError.invalidConfig("Vision Batch 必须在 1...min(Context, 128)。")
        }
        guard contextUBatch >= 1 && contextUBatch <= contextBatch else {
            throw LabError.invalidConfig("Vision uBatch 必须在 1...Vision Batch。")
        }
        return self
    }
}

struct GenerationMetrics: Sendable {
    let text: String
    let generatedTokens: Int
    let promptTokens: Int
    let ttftSeconds: Double
    let generationSeconds: Double
    let tokensPerSecond: Double
}

struct ModelMetrics: Sendable {
    let description: String
    let sizeGiB: Double
    let paramsB: Double
    let loadSeconds: Double
    let runtimeSummary: String
}

struct VisionLoadMetrics: Sendable {
    let headroomBeforeReleaseMiB: Int
    let headroomAfterReleaseMiB: Int
    let headroomAfterMMProjMiB: Int
    let headroomAfterContextMiB: Int

    var summary: String {
        """
        Headroom before context release: \(headroomBeforeReleaseMiB) MiB
        Headroom after context release: \(headroomAfterReleaseMiB) MiB
        Headroom after mmproj load: \(headroomAfterMMProjMiB) MiB
        Headroom after vision context: \(headroomAfterContextMiB) MiB
        """
    }
}

struct VisionProbeMetrics: Sendable {
    let fileName: String
    let fileSizeMiB: Int
    let headroomBeforeMiB: Int
    let headroomAfterMiB: Int
    let progressCode: Int

    var summary: String {
        """
        File: \(fileName)
        File size: \(fileSizeMiB) MiB
        Headroom before projector-only init: \(headroomBeforeMiB) MiB
        Headroom after projector-only init: \(headroomAfterMiB) MiB
        Probe progress code: \(progressCode)
        """
    }
}

struct CoexistenceProbeMetrics: Sendable {
    let mode: String
    let fileName: String
    let fileSizeMiB: Int
    let processHeadroomBeforeMiB: Int
    let processHeadroomAfterMiB: Int
    let metalAllocatedBeforeMiB: Int
    let metalAllocatedAfterMiB: Int
    let metalRecommendedMiB: Int
    let progressCode: Int

    var summary: String {
        """
        Mode: \(mode)
        File: \(fileName)
        File size: \(fileSizeMiB) MiB
        Process headroom: \(processHeadroomBeforeMiB) → \(processHeadroomAfterMiB) MiB
        Metal allocated: \(metalAllocatedBeforeMiB) → \(metalAllocatedAfterMiB) MiB
        Metal recommended max: \(metalRecommendedMiB) MiB
        Progress: \(progressCode)
        """
    }
}

struct SystemDiagnostics: Sendable {
    let availableMiB: Int
    let residentMiB: Int
    let virtualMiB: Int
    let physFootprintMiB: Int
    let extendedVA: Int32
    let increasedMemoryLimit: Int32

    private func entitlementText(_ value: Int32) -> String {
        switch value {
        case 1: return "YES"
        case 0: return "NO"
        default: return "UNKNOWN"
        }
    }

    var summary: String {
        """
        os_proc_available_memory: \(availableMiB) MiB
        resident_size: \(residentMiB) MiB
        phys_footprint: \(physFootprintMiB) MiB
        virtual_size: \(virtualMiB) MiB
        profile extended-virtual-addressing: \(entitlementText(extendedVA))
        profile increased-memory-limit: \(entitlementText(increasedMemoryLimit))
        """
    }
}

struct VisionBootstrapMetrics: Sendable {
    let headroomStartMiB: Int
    let headroomAfterVocabMiB: Int
    let headroomAfterMMProjMiB: Int
    let headroomAfterFullModelMiB: Int
    let headroomAfterContextMiB: Int
    let metalBeforeContextMiB: Int
    let metalAfterContextMiB: Int
    let metalRecommendedMiB: Int
    let requestedContext: Int
    let requestedBatch: Int
    let requestedUBatch: Int

    var summary: String {
        """
        Projector-first bootstrap: PASS
        Headroom start: \(headroomStartMiB) MiB
        After vocab-only model: \(headroomAfterVocabMiB) MiB
        After mmproj: \(headroomAfterMMProjMiB) MiB
        After full model: \(headroomAfterFullModelMiB) MiB
        After vision context: \(headroomAfterContextMiB) MiB
        """
    }
}

enum ResourceGovernorState: String, Sendable {
    case bypass = "BYPASS"
    case nominal = "NOMINAL"
    case guarded = "GUARDED"
    case constrained = "CONSTRAINED"
}

struct StagedVisionMetrics: Sendable {
    let text: String
    let promptTokens: Int
    let imageTokens: Int
    let projectionDimension: Int
    let generatedTokens: Int
    let finalPosition: Int
    let inputPositions: Int
    let requestedMaxTokens: Int
    let effectiveMaxTokens: Int
    let imageEncodeSeconds: Double
    let fullModelLoadSeconds: Double
    let contextCreateSeconds: Double
    let generationSeconds: Double
    let inferenceMode: VisionInferenceMode
    let imageCacheHit: Bool
    let residentModelHit: Bool
    let residentContextHit: Bool
    let kvReuseHit: Bool
    let imageCacheBytes: UInt64
    let resourceGovernorState: ResourceGovernorState
    let resourceHeadroomBeforeMiB: Int
    let resourceHeadroomAfterReleaseMiB: Int
    let resourceReleasedResidentBeforeEncode: Bool
    let resourceAdjustedVision: Bool
    let resourceRequestedImageTokens: Int
    let resourceEffectiveImageTokens: Int

    var tokensPerSecond: Double {
        guard generationSeconds > 0 else { return 0 }
        return Double(generatedTokens) / generationSeconds
    }

    var summary: String {
        """
        Staged vision: PASS
        Prompt/media tokens: \(promptTokens)
        Image tokens: \(imageTokens)
        Projection dim: \(projectionDimension)
        Generated: \(generatedTokens)
        Input positions: \(inputPositions)
        Requested Max Tokens: \(requestedMaxTokens)
        Effective output budget: \(effectiveMaxTokens)
        Final position: \(finalPosition)
        Image encode: \(String(format: "%.3f", imageEncodeSeconds)) s
        Full model load: \(String(format: "%.3f", fullModelLoadSeconds)) s
        Context create: \(String(format: "%.3f", contextCreateSeconds)) s
        Generation: \(String(format: "%.3f", generationSeconds)) s
        Image cache: \(imageCacheHit ? "HIT" : "MISS") · \(imageCacheBytes) bytes
        Resident model: \(residentModelHit ? "HIT" : "MISS")
        Resident context: \(residentContextHit ? "HIT" : "MISS")
        KV reuse: \(kvReuseHit ? "HIT" : "MISS")
        Resource governor: \(resourceGovernorState.rawValue)
        Resource headroom: \(resourceHeadroomBeforeMiB) → \(resourceHeadroomAfterReleaseMiB) MiB
        Resident released before encode: \(resourceReleasedResidentBeforeEncode ? "YES" : "NO")
        Vision tokens requested/effective: \(resourceRequestedImageTokens)/\(resourceEffectiveImageTokens)
        """
    }
}


struct VisionEmbeddingCacheMetrics: Sendable {
    let cacheURL: URL
    let cacheHit: Bool
    let imageTokens: Int
    let projectionDimension: Int
    let cacheBytes: UInt64
    let imageEncodeSeconds: Double
    let releasedTextRuntime: Bool
}

struct VisionMetrics: Sendable {
    let generation: GenerationMetrics
    let mediaTokens: Int
    let visionPrefillSeconds: Double
}

enum LabError: LocalizedError {
    case invalidConfig(String)
    case modelLoadFailed
    case contextCreateFailed
    case noModel
    case noVision
    case tokenizerFailed
    case promptTooLong(Int, Int)
    case decodeFailed(Int32)
    case emptyOutput
    case mmprojLoadFailed
    case mmprojNotVision
    case imageLoadFailed
    case visionTokenizeFailed(Int32)
    case visionEvalFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidConfig(let message): return message
        case .modelLoadFailed: return "主模型加载失败。"
        case .contextCreateFailed: return "Context 创建失败。"
        case .noModel: return "请先加载主模型并应用运行配置。"
        case .noVision: return "请先加载视觉模块 mmproj。"
        case .tokenizerFailed: return "Prompt tokenization 失败。"
        case .promptTooLong(let used, let limit): return "Prompt 已占用 \(used) tokens，超过 Context \(limit)。"
        case .decodeFailed(let code): return "llama_decode() 失败，code=\(code)。"
        case .emptyOutput: return "模型没有生成有效文本。"
        case .mmprojLoadFailed: return "mmproj 加载失败。"
        case .mmprojNotVision: return "该 mmproj 没有报告 vision capability。"
        case .imageLoadFailed: return "图片读取/解码失败。"
        case .visionTokenizeFailed(let code): return "视觉 prompt tokenization 失败，code=\(code)。"
        case .visionEvalFailed(let code): return "视觉 prefill/eval 失败，code=\(code)。"
        }
    }
}
