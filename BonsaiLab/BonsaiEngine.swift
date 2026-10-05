import Foundation
import CryptoKit
import Darwin
import Metal
import llama

private final class StagedVisionStreamBox {
    private let onDelta: @Sendable (String) -> Void
    private var pending = Data()

    init(onDelta: @escaping @Sendable (String) -> Void) {
        self.onDelta = onDelta
    }

    func consume(bytes: UnsafePointer<CChar>?, length: Int) {
        guard let bytes, length > 0 else { return }
        let raw = UnsafeRawPointer(bytes).assumingMemoryBound(to: UInt8.self)
        pending.append(raw, count: length)
        if let text = String(data: pending, encoding: .utf8) {
            pending.removeAll(keepingCapacity: true)
            if !text.isEmpty { onDelta(text) }
        }
    }

    func flush() {
        guard !pending.isEmpty else { return }
        let text = String(decoding: pending, as: UTF8.self)
        pending.removeAll(keepingCapacity: false)
        if !text.isEmpty { onDelta(text) }
    }
}

private let stagedVisionStreamCallback:
    @convention(c) (UnsafePointer<CChar>?, Int, UnsafeMutableRawPointer?) -> Void = {
        bytes, length, opaque in
        guard let opaque else { return }
        let box = Unmanaged<StagedVisionStreamBox>
            .fromOpaque(opaque)
            .takeUnretainedValue()
        box.consume(bytes: bytes, length: length)
    }

actor BonsaiEngine {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var visionContext: OpaquePointer?
    private var visionVocabModel: OpaquePointer?

    private var modelScopedURL: URL?
    private var mmprojScopedURL: URL?
    private var hasModelScope = false
    private var hasMMProjScope = false
    private var stagedResidentModelScopedURL: URL?
    private var hasStagedResidentModelScope = false
    private var backendInitialized = false
    private var appliedRuntime = RuntimeConfig.safe

    // RC1.23.2 experimental API-only prefix reuse state.
    // This is valid only for the currently resident llama context.
    private var apiVisionPrefixReuseKey: String?
    private var apiVisionPrefixPositions: Int32 = 0

    private let stageKey = "BonsaiLabLastStage"

    private func mark(_ stage: String) {
        UserDefaults.standard.set(stage, forKey: stageKey)
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: "BonsaiLabLastStageTime"
        )
        UserDefaults.standard.synchronize()

        let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(
            at: supportURL,
            withIntermediateDirectories: true
        )
        let engineStageURL = supportURL.appendingPathComponent(
            "bonsai_engine_stage.txt"
        )
        try? (stage + "\n").write(
            to: engineStageURL,
            atomically: true,
            encoding: .utf8
        )
    }

    func loadModel(url: URL, runtime: RuntimeConfig) throws -> ModelMetrics {
        let config = try runtime.validated()
        mark("MODEL_00_RESET_BEGIN")
        unloadAll()
        mark("MODEL_00_RESET_DONE")

        if config.disableMetalTensorAPI {
            setenv("GGML_METAL_TENSOR_DISABLE", "1", 1)
        } else {
            unsetenv("GGML_METAL_TENSOR_DISABLE")
        }
        mark("MODEL_01_ENV_READY")

        if !backendInitialized {
            mark("MODEL_02_BACKEND_INIT_BEGIN")
            llama_backend_init()
            backendInitialized = true
            mark("MODEL_03_BACKEND_INIT_DONE")
        }

        let scoped = url.startAccessingSecurityScopedResource()
        modelScopedURL = url
        hasModelScope = scoped
        mark("MODEL_04_FILE_SCOPE_DONE")

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = Int32(config.gpuLayers)
        modelParams.load_mode = config.loadMode == .mmap
            ? LLAMA_LOAD_MODE_MMAP
            : LLAMA_LOAD_MODE_NONE

        mark("MODEL_05_LOAD_BEGIN")
        let loadStart = DispatchTime.now().uptimeNanoseconds
        guard let loadedModel = llama_model_load_from_file(url.path, modelParams) else {
            mark("MODEL_05_LOAD_NULL")
            stopModelScope()
            throw LabError.modelLoadFailed
        }
        let loadEnd = DispatchTime.now().uptimeNanoseconds
        mark("MODEL_06_LOAD_DONE")

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(config.context)
        contextParams.n_batch = UInt32(config.batch)
        contextParams.n_ubatch = UInt32(config.ubatch)
        // C2-B deliberately preserves the validated single-sequence context.
        contextParams.n_seq_max = 1
        contextParams.n_outputs_max = 1
        contextParams.n_outputs_max_per_seq = 1
        contextParams.swa_full = config.swaFull
        contextParams.kv_unified = config.kvUnified
        contextParams.offload_kqv = config.offloadKQV
        contextParams.op_offload = config.opOffload
        contextParams.flash_attn_type = config.flashAttention
            ? LLAMA_FLASH_ATTN_TYPE_ENABLED
            : LLAMA_FLASH_ATTN_TYPE_DISABLED

        let cpuCount = ProcessInfo.processInfo.processorCount
        let threads = max(1, min(6, cpuCount - 2))
        contextParams.n_threads = Int32(threads)
        contextParams.n_threads_batch = Int32(threads)

        mark("MODEL_07_CONTEXT_CREATE_BEGIN")
        guard let loadedContext = llama_init_from_model(loadedModel, contextParams) else {
            mark("MODEL_07_CONTEXT_CREATE_NULL")
            llama_model_free(loadedModel)
            stopModelScope()
            throw LabError.contextCreateFailed
        }
        mark("MODEL_08_CONTEXT_CREATE_DONE")

        model = loadedModel
        context = loadedContext
        vocab = llama_model_get_vocab(loadedModel)
        appliedRuntime = config

        var descBuffer = [CChar](repeating: 0, count: 512)
        _ = llama_model_desc(loadedModel, &descBuffer, descBuffer.count)
        let desc = String(cString: descBuffer)

        let loadSeconds = Double(loadEnd - loadStart) / 1_000_000_000.0
        let metrics = ModelMetrics(
            description: desc,
            sizeGiB: Double(llama_model_size(loadedModel)) / 1_073_741_824.0,
            paramsB: Double(llama_model_n_params(loadedModel)) / 1_000_000_000.0,
            loadSeconds: loadSeconds,
            runtimeSummary: config.summary
        )

        persistSystemDiagnostics(prefix: "BonsaiLabModel")
        mark("MODEL_09_READY")
        return metrics
    }

    func loadVision(
        mmprojURL: URL,
        config: VisionConfig
    ) throws -> VisionLoadMetrics {
        guard let model else { throw LabError.noModel }
        let vision = try config.validated()

        unloadVision()

        let scoped = mmprojURL.startAccessingSecurityScopedResource()
        mmprojScopedURL = mmprojURL
        hasMMProjScope = scoped

        let beforeRelease = availableHeadroomMiB()
        UserDefaults.standard.set(
            beforeRelease,
            forKey: "BonsaiLabVisionHeadroomBeforeReleaseMiB"
        )

        // Mobile low-peak rule:
        // free the text KV/compute graph before mtmd_init_from_file().
        // The mmap-backed model weights stay loaded.
        mark("VISION_00_CONTEXT_RELEASE_BEGIN")
        if let context {
            llama_free(context)
            self.context = nil
        }
        mark("VISION_00_CONTEXT_RELEASE_DONE")

        let afterRelease = availableHeadroomMiB()
        UserDefaults.standard.set(
            afterRelease,
            forKey: "BonsaiLabVisionHeadroomAfterReleaseMiB"
        )

        // Match Prism/PocketPal-style conservative projector init:
        // CPU projector, no warmup, AUTO flash attention, no custom batch cap.
        mark("VISION_01_MMPROJ_LOAD_BEGIN")
        var params = mtmd_context_params_default()
        params.use_gpu = vision.useGPU
        params.print_timings = false
        params.n_threads = Int32(
            max(1, min(4, ProcessInfo.processInfo.processorCount - 2))
        )
        params.warmup = vision.warmup
        params.image_max_tokens = Int32(vision.imageMaxTokens)
        params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO

        guard let loadedVision = mtmd_init_from_file(
            mmprojURL.path,
            model,
            params
        ) else {
            mark("VISION_01_MMPROJ_LOAD_NULL")
            stopMMProjScope()

            // Restore a text context so a recoverable projector failure
            // does not leave the app unusable.
            self.context = try? makeContext(
                model: model,
                config: appliedRuntime
            )
            throw LabError.mmprojLoadFailed
        }

        let afterMMProj = availableHeadroomMiB()
        UserDefaults.standard.set(
            afterMMProj,
            forKey: "BonsaiLabVisionHeadroomAfterMMProjMiB"
        )
        mark("VISION_02_MMPROJ_LOAD_DONE")

        guard mtmd_support_vision(loadedVision) else {
            mark("VISION_02_CAPABILITY_FAIL")
            mtmd_free(loadedVision)
            stopMMProjScope()
            self.context = try? makeContext(
                model: model,
                config: appliedRuntime
            )
            throw LabError.mmprojNotVision
        }

        // Ensure the vision prompt actually fits. Keep the batch tiny while
        // raising only n_ctx enough for image embeddings + answer budget.
        var visionRuntime = appliedRuntime
        visionRuntime.context = max(
            appliedRuntime.context,
            min(2048, vision.imageMaxTokens + 512)
        )
        visionRuntime.batch = min(appliedRuntime.batch, 16)
        visionRuntime.ubatch = min(appliedRuntime.ubatch, visionRuntime.batch)
        visionRuntime.kvUnified = true

        mark("VISION_03_CONTEXT_RECREATE_BEGIN")
        guard let restoredContext = try? makeContext(
            model: model,
            config: visionRuntime
        ) else {
            mtmd_free(loadedVision)
            stopMMProjScope()
            mark("VISION_03_CONTEXT_RECREATE_FAIL")
            throw LabError.contextCreateFailed
        }

        context = restoredContext
        appliedRuntime = visionRuntime
        visionContext = loadedVision

        let afterContext = availableHeadroomMiB()
        UserDefaults.standard.set(
            afterContext,
            forKey: "BonsaiLabVisionHeadroomAfterContextMiB"
        )
        mark("VISION_04_READY")

        return VisionLoadMetrics(
            headroomBeforeReleaseMiB: beforeRelease,
            headroomAfterReleaseMiB: afterRelease,
            headroomAfterMMProjMiB: afterMMProj,
            headroomAfterContextMiB: afterContext
        )
    }

    func loadVisionProjectorFirst(
        modelURL: URL,
        mmprojURL: URL,
        runtime: RuntimeConfig,
        config: VisionConfig
    ) throws -> VisionBootstrapMetrics {
        let baseRuntime = try runtime.validated()
        let vision = try config.validated()

        guard baseRuntime.loadMode == .mmap else {
            throw LabError.invalidConfig(
                "Projector-first 必须使用 MMAP；RC1.6 已证明 LOAD NONE 会在主模型加载阶段闪退。"
            )
        }

        unloadAll(releaseStagedResident: false)

        if baseRuntime.disableMetalTensorAPI {
            setenv("GGML_METAL_TENSOR_DISABLE", "1", 1)
        } else {
            unsetenv("GGML_METAL_TENSOR_DISABLE")
        }

        if !backendInitialized {
            mark("BOOT_00_BACKEND_INIT_BEGIN")
            llama_backend_init()
            backendInitialized = true
            mark("BOOT_00_BACKEND_INIT_DONE")
        }

        let modelScope = modelURL.startAccessingSecurityScopedResource()
        modelScopedURL = modelURL
        hasModelScope = modelScope

        let mmprojScope = mmprojURL.startAccessingSecurityScopedResource()
        mmprojScopedURL = mmprojURL
        hasMMProjScope = mmprojScope

        let headroomStart = availableHeadroomMiB()
        UserDefaults.standard.set(
            headroomStart,
            forKey: "BonsaiLabBootstrapHeadroomStartMiB"
        )
        UserDefaults.standard.synchronize()

        // Phase 1: load only metadata + vocab from the main GGUF.
        // This gives mtmd the correct vocab, embedding width, and RoPE type
        // without mapping/allocating the 27B weights.
        mark("BOOT_01_VOCAB_MODEL_BEGIN")
        var vocabParams = llama_model_default_params()
        vocabParams.vocab_only = true
        vocabParams.n_gpu_layers = 0
        vocabParams.load_mode = LLAMA_LOAD_MODE_MMAP

        guard let bootstrapModel = llama_model_load_from_file(
            modelURL.path,
            vocabParams
        ) else {
            mark("BOOT_01_VOCAB_MODEL_NULL")
            stopMMProjScope()
            stopModelScope()
            throw LabError.modelLoadFailed
        }
        visionVocabModel = bootstrapModel
        mark("BOOT_01_VOCAB_MODEL_DONE")

        let afterVocab = availableHeadroomMiB()
        UserDefaults.standard.set(
            afterVocab,
            forKey: "BonsaiLabBootstrapHeadroomAfterVocabMiB"
        )
        UserDefaults.standard.synchronize()

        // Phase 2: initialize the projector while the 27B weights are NOT
        // resident. RC1.4 proved this path can complete on the device.
        mark("BOOT_02_MMPROJ_BEGIN")
        var mtmdParams = mtmd_context_params_default()
        mtmdParams.use_gpu = vision.useGPU
        mtmdParams.print_timings = false
        mtmdParams.n_threads = Int32(
            max(1, min(4, ProcessInfo.processInfo.processorCount - 2))
        )
        mtmdParams.warmup = false
        mtmdParams.image_max_tokens = Int32(vision.imageMaxTokens)
        mtmdParams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO

        guard let loadedVision = mtmd_init_from_file(
            mmprojURL.path,
            bootstrapModel,
            mtmdParams
        ) else {
            mark("BOOT_02_MMPROJ_NULL")
            llama_model_free(bootstrapModel)
            visionVocabModel = nil
            stopMMProjScope()
            stopModelScope()
            throw LabError.mmprojLoadFailed
        }

        guard mtmd_support_vision(loadedVision) else {
            mark("BOOT_02_CAPABILITY_FAIL")
            mtmd_free(loadedVision)
            llama_model_free(bootstrapModel)
            visionVocabModel = nil
            stopMMProjScope()
            stopModelScope()
            throw LabError.mmprojNotVision
        }

        visionContext = loadedVision
        mark("BOOT_02_MMPROJ_DONE")

        let afterMMProj = availableHeadroomMiB()
        UserDefaults.standard.set(
            afterMMProj,
            forKey: "BonsaiLabBootstrapHeadroomAfterMMProjMiB"
        )
        UserDefaults.standard.synchronize()

        // Phase 3: with the projector already allocated, mmap the full 27B.
        mark("BOOT_03_FULL_MODEL_BEGIN")
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = Int32(baseRuntime.gpuLayers)
        modelParams.load_mode = LLAMA_LOAD_MODE_MMAP

        guard let loadedModel = llama_model_load_from_file(
            modelURL.path,
            modelParams
        ) else {
            mark("BOOT_03_FULL_MODEL_NULL")
            unloadVision()
            stopModelScope()
            throw LabError.modelLoadFailed
        }

        model = loadedModel
        vocab = llama_model_get_vocab(loadedModel)
        mark("BOOT_03_FULL_MODEL_DONE")

        let afterFullModel = availableHeadroomMiB()
        UserDefaults.standard.set(
            afterFullModel,
            forKey: "BonsaiLabBootstrapHeadroomAfterFullModelMiB"
        )
        UserDefaults.standard.synchronize()

        // Phase 4: create an explicitly sized low-memory vision context.
        // RC1.7 failed at an implicit 1024-token context. RC1.8 decouples
        // the image token budget from n_ctx and exposes a 256/512/768/1024 ladder.
        var visionRuntime = baseRuntime
        visionRuntime.context = vision.contextTokens
        visionRuntime.batch = vision.contextBatch
        visionRuntime.ubatch = vision.contextUBatch
        visionRuntime.kvUnified = true
        visionRuntime.loadMode = .mmap

        if vision.lowMemoryContext {
            visionRuntime.flashAttention = false
            visionRuntime.offloadKQV = false
            visionRuntime.opOffload = false
            visionRuntime.swaFull = false
        }

        let metalBeforeContext = metalSnapshotMiB()
        UserDefaults.standard.set(
            metalBeforeContext.allocated,
            forKey: "BonsaiLabBootstrapMetalBeforeContextMiB"
        )
        UserDefaults.standard.set(
            metalBeforeContext.recommended,
            forKey: "BonsaiLabBootstrapMetalRecommendedMiB"
        )
        UserDefaults.standard.set(
            visionRuntime.context,
            forKey: "BonsaiLabBootstrapRequestedContext"
        )
        UserDefaults.standard.set(
            visionRuntime.batch,
            forKey: "BonsaiLabBootstrapRequestedBatch"
        )
        UserDefaults.standard.set(
            visionRuntime.ubatch,
            forKey: "BonsaiLabBootstrapRequestedUBatch"
        )
        UserDefaults.standard.synchronize()

        mark(
            "BOOT_04_CONTEXT_BEGIN_CTX_\(visionRuntime.context)_B\(visionRuntime.batch)_U\(visionRuntime.ubatch)"
        )
        guard let loadedContext = try? makeContext(
            model: loadedModel,
            config: visionRuntime
        ) else {
            mark("BOOT_04_CONTEXT_FAIL")
            unloadAll()
            throw LabError.contextCreateFailed
        }

        context = loadedContext
        appliedRuntime = visionRuntime
        mark("BOOT_04_CONTEXT_DONE")

        let afterContext = availableHeadroomMiB()
        let metalAfterContext = metalSnapshotMiB()

        UserDefaults.standard.set(
            afterContext,
            forKey: "BonsaiLabBootstrapHeadroomAfterContextMiB"
        )
        UserDefaults.standard.set(
            metalAfterContext.allocated,
            forKey: "BonsaiLabBootstrapMetalAfterContextMiB"
        )
        UserDefaults.standard.synchronize()

        persistSystemDiagnostics(prefix: "BonsaiLabBootstrap")
        mark("BOOT_99_READY")

        return VisionBootstrapMetrics(
            headroomStartMiB: headroomStart,
            headroomAfterVocabMiB: afterVocab,
            headroomAfterMMProjMiB: afterMMProj,
            headroomAfterFullModelMiB: afterFullModel,
            headroomAfterContextMiB: afterContext,
            metalBeforeContextMiB: metalBeforeContext.allocated,
            metalAfterContextMiB: metalAfterContext.allocated,
            metalRecommendedMiB: metalBeforeContext.recommended,
            requestedContext: visionRuntime.context,
            requestedBatch: visionRuntime.batch,
            requestedUBatch: visionRuntime.ubatch
        )
    }

    private func makeVisionCacheURL(
        modelURL: URL,
        mmprojURL: URL,
        imageURL: URL,
        imageMaxTokens: Int
    ) throws -> URL {
        let imageData = try Data(
            contentsOf: imageURL,
            options: [.mappedIfSafe]
        )
        let mmprojAttrs = try FileManager.default.attributesOfItem(
            atPath: mmprojURL.path
        )
        let mmprojSize =
            (mmprojAttrs[.size] as? NSNumber)?.uint64Value ?? 0

        var hasher = SHA256()
        hasher.update(data: imageData)
        hasher.update(
            data: Data(
                (
                    "BVCACHE1|"
                    + modelURL.lastPathComponent + "|"
                    + mmprojURL.lastPathComponent + "|"
                    + String(mmprojSize) + "|"
                    + String(imageMaxTokens)
                ).utf8
            )
        )

        let digest = hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined()

        let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let cacheDirectory = supportURL.appendingPathComponent(
            "BonsaiVisionCache",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )

        return cacheDirectory.appendingPathComponent(
            digest + ".bvcache"
        )
    }

    private func makeMLXVisionCacheURL(
        modelURL: URL,
        weightsURL: URL,
        imageURL: URL,
        imageMaxTokens: Int
    ) throws -> URL {
        let imageData = try Data(
            contentsOf: imageURL,
            options: [.mappedIfSafe]
        )
        let weightAttrs =
            try FileManager.default.attributesOfItem(
                atPath: weightsURL.path
            )
        let weightSize =
            (weightAttrs[.size] as? NSNumber)?
                .uint64Value ?? 0

        var hasher = SHA256()
        hasher.update(data: imageData)
        hasher.update(
            data: Data(
                (
                    "BVCACHE1|MLX-HARDCUT-V1|"
                    + modelURL.lastPathComponent + "|"
                    + weightsURL.lastPathComponent + "|"
                    + String(weightSize) + "|"
                    + String(imageMaxTokens)
                ).utf8
            )
        )

        let digest = hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined()

        let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let directory =
            supportURL.appendingPathComponent(
                "BonsaiVisionCache",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent(
            digest + ".bvcache"
        )
    }

    func writeMLXProjectedVisionCache(
        modelURL: URL,
        weightsURL: URL,
        imageURL: URL,
        embeddingData: Data,
        nTokens: Int,
        projectionDimension: Int,
        gridX: Int,
        gridY: Int,
        imageMaxTokens: Int
    ) throws -> URL {
        guard
            nTokens > 0,
            projectionDimension > 0,
            gridX > 0,
            gridY > 0,
            gridX * gridY == nTokens,
            embeddingData.count ==
                nTokens
                * projectionDimension
                * MemoryLayout<Float>.size
        else {
            throw LabError.invalidConfig(
                "MLX projected embedding packet shape invalid."
            )
        }

        let modelScope =
            modelURL.startAccessingSecurityScopedResource()
        let weightsScope =
            weightsURL.startAccessingSecurityScopedResource()
        let imageScope =
            imageURL.startAccessingSecurityScopedResource()
        defer {
            if modelScope {
                modelURL.stopAccessingSecurityScopedResource()
            }
            if weightsScope {
                weightsURL.stopAccessingSecurityScopedResource()
            }
            if imageScope {
                imageURL.stopAccessingSecurityScopedResource()
            }
        }

        let cacheURL = try makeMLXVisionCacheURL(
            modelURL: modelURL,
            weightsURL: weightsURL,
            imageURL: imageURL,
            imageMaxTokens: imageMaxTokens
        )

        let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let stageURL = supportURL.appendingPathComponent(
            "bonsai_mlx_injection_stage.txt"
        )

        var errorBuffer = [CChar](
            repeating: 0,
            count: 4_096
        )

        let result: BonsaiVisionCacheResult =
            embeddingData.withUnsafeBytes {
                rawBuffer in
                let floats =
                    rawBuffer.bindMemory(to: Float.self)

                return cacheURL.path.withCString {
                    cachePath in
                    stageURL.path.withCString {
                        stagePath in
                        BonsaiWriteProjectedVisionCache(
                            floats.baseAddress,
                            Int32(nTokens),
                            Int32(projectionDimension),
                            Int32(gridX),
                            Int32(gridY),
                            Int32(imageMaxTokens),
                            cachePath,
                            &errorBuffer,
                            errorBuffer.count,
                            stagePath
                        )
                    }
                }
            }

        guard result.code == 0 else {
            throw LabError.invalidConfig(
                "MLX embedding cache write failed "
                + "code=\(result.code): "
                + String(cString: errorBuffer)
            )
        }

        trimVisionCache(keeping: cacheURL)
        mark("MLX_INJECT_12_CACHE_READY")
        return cacheURL
    }

    private func trimVisionCache(
        keeping touchedURL: URL,
        maxFiles: Int = 8,
        maxBytes: UInt64 = 128 * 1_048_576
    ) {
        let manager = FileManager.default
        let directory = touchedURL.deletingLastPathComponent()

        try? manager.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: touchedURL.path
        )

        guard
            let urls = try? manager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .contentModificationDateKey,
                    .fileSizeKey,
                ],
                options: [.skipsHiddenFiles]
            )
        else {
            return
        }

        let entries = urls.compactMap { url -> (
            URL,
            Date,
            UInt64
        )? in
            guard
                let values = try? url.resourceValues(
                    forKeys: [
                        .contentModificationDateKey,
                        .fileSizeKey,
                    ]
                )
            else {
                return nil
            }

            return (
                url,
                values.contentModificationDate ?? .distantPast,
                UInt64(max(0, values.fileSize ?? 0))
            )
        }
        .sorted { $0.1 > $1.1 }

        var kept = 0
        var bytes: UInt64 = 0
        for entry in entries {
            let wouldExceedFiles = kept >= maxFiles
            let wouldExceedBytes =
                kept > 0 && bytes + entry.2 > maxBytes

            if wouldExceedFiles || wouldExceedBytes {
                try? manager.removeItem(at: entry.0)
            } else {
                kept += 1
                bytes += entry.2
            }
        }
    }


    func prepareVisionEmbeddingCache(
        modelURL: URL,
        mmprojURL: URL,
        imageURL: URL,
        vision: VisionConfig
    ) throws -> VisionEmbeddingCacheMetrics {
        let validatedVision = try vision.validated()

        // RC1.21.1: security scopes must exist BEFORE the cache key is
        // computed. makeVisionCacheURL reads the image bytes and mmproj
        // file metadata. The first request can inherit temporary picker
        // access, but the second request cannot rely on that.
        let modelScope =
            modelURL.startAccessingSecurityScopedResource()
        let mmprojScope =
            mmprojURL.startAccessingSecurityScopedResource()
        let imageScope =
            imageURL.startAccessingSecurityScopedResource()
        defer {
            if modelScope {
                modelURL.stopAccessingSecurityScopedResource()
            }
            if mmprojScope {
                mmprojURL.stopAccessingSecurityScopedResource()
            }
            if imageScope {
                imageURL.stopAccessingSecurityScopedResource()
            }
        }

        mark("TWOPHASE_A00_SCOPE_READY")

        let cacheURL = try makeVisionCacheURL(
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            imageURL: imageURL,
            imageMaxTokens:
                validatedVision.imageMaxTokens
        )

        let validCache = cacheURL.path.withCString {
            BonsaiVisionCacheIsValid(
                $0,
                Int32(validatedVision.imageMaxTokens)
            ) == 1
        }

        if validCache {
            trimVisionCache(keeping: cacheURL)
            let size = (
                try? cacheURL.resourceValues(
                    forKeys: [.fileSizeKey]
                ).fileSize
            ) ?? 0
            mark("TWOPHASE_A00_CACHE_HIT")
            return VisionEmbeddingCacheMetrics(
                cacheURL: cacheURL,
                cacheHit: true,
                imageTokens: 0,
                projectionDimension: 0,
                cacheBytes: UInt64(max(0, size)),
                imageEncodeSeconds: 0,
                releasedTextRuntime: false
            )
        }

        // Hard phase boundary: no full 27B model/context may coexist
        // with mtmd_init_from_file on this device.
        unloadAll()

        if !backendInitialized {
            llama_backend_init()
            backendInitialized = true
        }

        let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(
            at: supportURL,
            withIntermediateDirectories: true
        )
        let stageURL = supportURL.appendingPathComponent(
            "bonsai_two_phase_vision_stage.txt"
        )

        var errorBuffer = [CChar](
            repeating: 0,
            count: 4_096
        )

        let result = modelURL.path.withCString {
            modelPath in
            mmprojURL.path.withCString {
                mmprojPath in
                imageURL.path.withCString {
                    imagePath in
                    cacheURL.path.withCString {
                        cachePath in
                        stageURL.path.withCString {
                            stagePath in
                            BonsaiPrepareVisionCache(
                                modelPath,
                                mmprojPath,
                                imagePath,
                                Int32(
                                    validatedVision
                                        .imageMaxTokens
                                ),
                                cachePath,
                                &errorBuffer,
                                errorBuffer.count,
                                stagePath
                            )
                        }
                    }
                }
            }
        }

        let stage = (
            try? String(
                contentsOf: stageURL,
                encoding: .utf8
            )
        )?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? "TWOPHASE_A_UNKNOWN"
        mark(stage)

        guard result.code == 0 else {
            throw LabError.invalidConfig(
                "Two-phase vision Phase A 失败 "
                + "code=\(result.code): "
                + String(cString: errorBuffer)
            )
        }

        trimVisionCache(keeping: cacheURL)

        // mtmd and vocab-only model are gone here. Reset the backend
        // itself as well so Phase B starts from a clean Metal state.
        if backendInitialized {
            llama_backend_free()
            backendInitialized = false
            mark("TWOPHASE_A100_BACKEND_RESET")
        }

        // Real-device evidence shows that creating a fresh 27B llama
        // context after mtmd/projector work in the same process can
        // terminate the app at llama_init_from_model. Do not cross that
        // unsafe boundary in-process. Persist the cache and require a
        // clean process before Phase B.
        mark("TWOPHASE_A110_RESTART_REQUIRED")

        return VisionEmbeddingCacheMetrics(
            cacheURL: cacheURL,
            cacheHit: false,
            imageTokens: Int(result.image_tokens),
            projectionDimension:
                Int(result.projection_dim),
            cacheBytes: UInt64(result.cache_bytes),
            imageEncodeSeconds:
                result.image_encode_ms / 1000.0,
            releasedTextRuntime: true
        )
    }

    func generateCachedVision(
        cacheURL: URL,
        imageMaxTokens: Int,
        systemPrompt: String,
        question: String,
        generation: GenerationConfig,
        reasoningEffort: String? = nil,
        requireFullOutputBudget: Bool = false,
        enablePrefixReuse: Bool = false,
        onDelta: (@Sendable (String) -> Void)? = nil
    ) throws -> VisionMetrics {
        guard
            let model,
            let context,
            let vocab
        else {
            throw LabError.noModel
        }

        let gen = try generation.validated(
            context: appliedRuntime.context
        )

        let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let stageURL = supportURL.appendingPathComponent(
            "bonsai_two_phase_vision_stage.txt"
        )

        var errorBuffer = [CChar](
            repeating: 0,
            count: 4_096
        )

        let reuseKey =
            cacheURL.path + "\n" + systemPrompt
        let effectivePrefixReuse = enablePrefixReuse

        let requestPrefixReuse =
            effectivePrefixReuse &&
            apiVisionPrefixReuseKey == reuseKey &&
            apiVisionPrefixPositions > 0

        if !effectivePrefixReuse {
            apiVisionPrefixReuseKey = nil
            apiVisionPrefixPositions = 0
        }

        let prefill = cacheURL.path.withCString {
            cachePath in
            systemPrompt.withCString {
                systemPtr in
                question.withCString {
                    questionPtr in
                    stageURL.path.withCString {
                        stagePath in
                        BonsaiPrefillCachedVision(
                            model,
                            context,
                            cachePath,
                            Int32(imageMaxTokens),
                            systemPtr,
                            questionPtr,
                            Int32(appliedRuntime.batch),
                            reasoningEffort == "none"
                                ? 1
                                : 0,
                            effectivePrefixReuse
                                ? 1
                                : 0,
                            requestPrefixReuse
                                ? apiVisionPrefixPositions
                                : 0,
                            Int32(appliedRuntime.context),
                            Int32(gen.maxTokens),
                            &errorBuffer,
                            errorBuffer.count,
                            stagePath
                        )
                    }
                }
            }
        }

        let stage = (
            try? String(
                contentsOf: stageURL,
                encoding: .utf8
            )
        )?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? "TWOPHASE_B_UNKNOWN"
        mark(stage)

        guard prefill.code == 0 else {
            if prefill.code == 9 {
                throw LabError.contextBudgetExceeded(
                    inputPositions:
                        Int(prefill.input_positions),
                    promptKVTokens:
                        Int(prefill.prompt_tokens),
                    requestedOutputTokens:
                        gen.maxTokens,
                    contextLimit:
                        appliedRuntime.context
                )
            }

            throw LabError.invalidConfig(
                "Two-phase vision Phase B 失败 "
                + "code=\(prefill.code): "
                + String(cString: errorBuffer)
            )
        }

        let positionalAvailable =
            appliedRuntime.context
            - Int(prefill.input_positions)
            - 1
        let kvAvailable =
            appliedRuntime.context
            - Int(prefill.prompt_tokens)
        let available =
            min(positionalAvailable, kvAvailable)
        guard available > 0 else {
            if requireFullOutputBudget {
                throw LabError.contextBudgetExceeded(
                    inputPositions:
                        Int(prefill.input_positions),
                    promptKVTokens:
                        Int(prefill.prompt_tokens),
                    requestedOutputTokens:
                        gen.maxTokens,
                    contextLimit:
                        appliedRuntime.context
                )
            }

            throw LabError.promptTooLong(
                Int(prefill.input_positions),
                appliedRuntime.context
            )
        }

        if requireFullOutputBudget,
           gen.maxTokens > available {
            throw LabError.contextBudgetExceeded(
                inputPositions:
                    Int(prefill.input_positions),
                promptKVTokens:
                    Int(prefill.prompt_tokens),
                requestedOutputTokens:
                    gen.maxTokens,
                contextLimit:
                    appliedRuntime.context
            )
        }

        let effectiveMaxTokens =
            requireFullOutputBudget
                ? gen.maxTokens
                : min(
                    gen.maxTokens,
                    available
                )

        let sampler = makeSampler(
            vocab: vocab,
            config: gen
        )
        defer {
            llama_sampler_free(sampler)
        }

        let generationStart =
            DispatchTime.now().uptimeNanoseconds
        let generated = try decodeGeneratedTokens(
            context: context,
            vocab: vocab,
            sampler: sampler,
            startPosition:
                Int32(prefill.input_positions),
            maxTokens: effectiveMaxTokens,
            stagePrefix: "TWOPHASE_VISION",
            onDelta: onDelta
        )
        let end =
            DispatchTime.now().uptimeNanoseconds

        guard !generated.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw LabError.emptyOutput
        }

        let generationSeconds = max(
            0.000001,
            Double(
                end - generationStart
            ) / 1_000_000_000.0
        )

        var prefixRetainedForReuse = false
        if effectivePrefixReuse,
           prefill.prefix_positions > 0 {
            prefixRetainedForReuse =
                BonsaiRetainVisionPrefixKV(
                    context,
                    prefill.prefix_positions
                ) == 1

            if prefixRetainedForReuse {
                apiVisionPrefixReuseKey = reuseKey
                apiVisionPrefixPositions =
                    prefill.prefix_positions
                mark(
                    "TWOPHASE_VISION_95_PREFIX_RETAINED"
                )
            } else {
                apiVisionPrefixReuseKey = nil
                apiVisionPrefixPositions = 0
                mark(
                    "TWOPHASE_VISION_96_PREFIX_CHECKPOINT_UNAVAILABLE"
                )
            }
        } else {
            apiVisionPrefixReuseKey = nil
            apiVisionPrefixPositions = 0
        }

        let decodeToFirstTokenSeconds: Double
        if let firstTokenTime = generated.firstTokenTime {
            decodeToFirstTokenSeconds =
                Double(
                    firstTokenTime - generationStart
                ) / 1_000_000_000.0
        } else {
            decodeToFirstTokenSeconds = 0
        }

        let base = GenerationMetrics(
            text: generated.text,
            generatedTokens: generated.count,
            promptTokens: Int(
                prefill.prompt_tokens
            ),
            effectiveMaxTokens: effectiveMaxTokens,
            terminationReason:
                generated.terminationReason,
            ttftSeconds:
                prefill.prefill_ms / 1000.0
                + decodeToFirstTokenSeconds,
            generationSeconds:
                generationSeconds,
            tokensPerSecond:
                Double(generated.count)
                / generationSeconds
        )

        mark("TWOPHASE_VISION_99_PASS")
        return VisionMetrics(
            generation: base,
            mediaTokens: Int(
                prefill.image_tokens
            ),
            visionPrefillSeconds:
                prefill.prefill_ms / 1000.0,
            prefixReuseHit:
                prefill.prefix_reuse_hit == 1,
            prefixPositions:
                Int(prefill.prefix_positions),
            prefixTextSeconds:
                prefill.prefix_text_ms / 1000.0,
            imagePrefillSeconds:
                prefill.image_prefill_ms / 1000.0,
            suffixPrefillSeconds:
                prefill.suffix_prefill_ms / 1000.0,
            suffixTokenCount:
                Int(prefill.suffix_token_count),
            suffixDecodeCalls:
                Int(prefill.suffix_decode_calls),
            suffixBatchCapacity:
                Int(prefill.suffix_batch_capacity),
            suffixUBatchCapacity:
                appliedRuntime.ubatch,
            suffixLastBatchTokens:
                Int(prefill.suffix_last_batch_tokens),
            suffixBatchUtilization:
                prefill.suffix_batch_utilization,
            prefixRetainedForReuse:
                prefixRetainedForReuse
        )
    }

    func runStagedVision(
        modelURL: URL,
        mmprojURL: URL,
        imageURL: URL,
        question: String,
        runtime: RuntimeConfig,
        vision: VisionConfig,
        generation: GenerationConfig,
        inferenceMode: VisionInferenceMode,
        resourceGovernorEnabled: Bool = true,
        onDelta: (@Sendable (String) -> Void)? = nil
    ) throws -> StagedVisionMetrics {
        let baseRuntime = try runtime.validated()
        let requestedVisionConfig = try vision.validated()

        guard baseRuntime.loadMode == .mmap else {
            throw LabError.invalidConfig(
                "Staged Vision 必须使用 MMAP 主模型。"
            )
        }

        // Keep the staged full model alive across repeated vision requests.
        // Ordinary text/vision state is still released before staged execution.
        unloadAll(releaseStagedResident: false)

        if baseRuntime.disableMetalTensorAPI {
            setenv("GGML_METAL_TENSOR_DISABLE", "1", 1)
        } else {
            unsetenv("GGML_METAL_TENSOR_DISABLE")
        }

        if !backendInitialized {
            mark("STAGED_00_BACKEND_INIT_BEGIN")
            llama_backend_init()
            backendInitialized = true
            mark("STAGED_00_BACKEND_INIT_DONE")
        }

        if stagedResidentModelScopedURL?.path != modelURL.path {
            BonsaiReleaseStagedResidentModel()
            stopStagedResidentModelScope()
        }

        let mmprojScope = mmprojURL.startAccessingSecurityScopedResource()
        let imageScope = imageURL.startAccessingSecurityScopedResource()

        defer {
            if mmprojScope {
                mmprojURL.stopAccessingSecurityScopedResource()
            }
            if imageScope {
                imageURL.stopAccessingSecurityScopedResource()
            }
        }

        let requestedCacheURL = try makeVisionCacheURL(
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            imageURL: imageURL,
            imageMaxTokens: requestedVisionConfig.imageMaxTokens
        )
        let requestedCacheHit = FileManager.default.fileExists(
            atPath: requestedCacheURL.path
        )

        let headroomBeforeGovernor = availableHeadroomMiB()
        var headroomAfterRelease = headroomBeforeGovernor
        var releasedResidentBeforeEncode = false
        var effectiveVisionConfig = requestedVisionConfig
        var governorState: ResourceGovernorState =
            resourceGovernorEnabled ? .nominal : .bypass

        if resourceGovernorEnabled && !requestedCacheHit {
            // v1 policy: preserve the user's requested quality whenever possible.
            // First remove resident state only when a new projector encode would
            // otherwise run with limited process headroom.
            if
                hasStagedResidentModelScope &&
                headroomBeforeGovernor < 2_048
            {
                BonsaiReleaseStagedResidentModel()
                stopStagedResidentModelScope()
                releasedResidentBeforeEncode = true
                headroomAfterRelease = availableHeadroomMiB()
                governorState = .guarded
                mark("RESOURCE_10_RESIDENT_RELEASED")
            }

            // Only degrade after lifecycle cleanup is insufficient.
            if
                headroomAfterRelease < 1_024 &&
                requestedVisionConfig.imageMaxTokens > VisionConfig.low512.imageMaxTokens
            {
                effectiveVisionConfig = .low512
                governorState = .constrained
                mark("RESOURCE_20_VISION_DOWNGRADE_512")
            } else if
                headroomAfterRelease < 1_536 &&
                requestedVisionConfig.imageMaxTokens > VisionConfig.mid768.imageMaxTokens
            {
                effectiveVisionConfig = .mid768
                governorState = .constrained
                mark("RESOURCE_20_VISION_DOWNGRADE_768")
            }
        }

        let visionConfig = try effectiveVisionConfig.validated()
        let gen = try generation.validated(
            context: visionConfig.contextTokens
        )

        let cacheURL: URL
        if visionConfig.imageMaxTokens == requestedVisionConfig.imageMaxTokens {
            cacheURL = requestedCacheURL
        } else {
            cacheURL = try makeVisionCacheURL(
                modelURL: modelURL,
                mmprojURL: mmprojURL,
                imageURL: imageURL,
                imageMaxTokens: visionConfig.imageMaxTokens
            )
        }

        // Resource release may have dropped the security scope associated
        // with the staged resident model. Reacquire it before native loading.
        if !hasStagedResidentModelScope {
            hasStagedResidentModelScope =
                modelURL.startAccessingSecurityScopedResource()
            stagedResidentModelScopedURL = modelURL
        }

        let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(
            at: supportURL,
            withIntermediateDirectories: true
        )

        let stageURL = supportURL.appendingPathComponent(
            "bonsai_staged_vision_stage.txt"
        )
        try? "STAGED_SWIFT_BEGIN\n".write(
            to: stageURL,
            atomically: true,
            encoding: .utf8
        )

        var output = [CChar](repeating: 0, count: 65_536)
        var errorBuffer = [CChar](repeating: 0, count: 4_096)

        let maxNew = gen.maxTokens
        let streamBox = onDelta.map { StagedVisionStreamBox(onDelta: $0) }
        let streamContext = streamBox.map {
            Unmanaged.passUnretained($0).toOpaque()
        }

        let bridgeResult = modelURL.path.withCString { modelPath in
            mmprojURL.path.withCString { mmprojPath in
                imageURL.path.withCString { imagePath in
                    question.withCString { questionPtr in
                        cacheURL.path.withCString { cachePath in
                            stageURL.path.withCString { stagePath in
                                BonsaiRunStagedVision(
                                    modelPath,
                                    mmprojPath,
                                    imagePath,
                                    questionPtr,
                                    Int32(visionConfig.imageMaxTokens),
                                    Int32(visionConfig.contextTokens),
                                    Int32(visionConfig.contextBatch),
                                    Int32(visionConfig.contextUBatch),
                                    Int32(baseRuntime.gpuLayers),
                                    Int32(maxNew),
                                    inferenceMode.bridgeValue,
                                    cachePath,
                                    &output,
                                    output.count,
                                    &errorBuffer,
                                    errorBuffer.count,
                                    stagePath,
                                    streamBox == nil ? nil : stagedVisionStreamCallback,
                                    streamContext
                                )
                            }
                        }
                    }
                }
            }
        }

        streamBox?.flush()

        let persistedStage = (
            try? String(
                contentsOf: stageURL,
                encoding: .utf8
            )
        )?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "STAGED_UNKNOWN"

        mark(persistedStage)

        guard bridgeResult.code == 0 else {
            let message = String(cString: errorBuffer)
            throw LabError.invalidConfig(
                "Staged Vision 失败 code=\(bridgeResult.code): \(message)"
            )
        }

        trimVisionCache(keeping: cacheURL)

        return StagedVisionMetrics(
            text: String(cString: output),
            promptTokens: Int(bridgeResult.prompt_tokens),
            imageTokens: Int(bridgeResult.image_tokens),
            projectionDimension: Int(bridgeResult.projection_dim),
            generatedTokens: Int(bridgeResult.generated_tokens),
            finalPosition: Int(bridgeResult.final_position),
            inputPositions: Int(bridgeResult.input_positions),
            requestedMaxTokens: Int(bridgeResult.requested_max_tokens),
            effectiveMaxTokens: Int(bridgeResult.effective_max_tokens),
            imageEncodeSeconds: bridgeResult.image_encode_ms / 1000.0,
            fullModelLoadSeconds: bridgeResult.full_model_load_ms / 1000.0,
            contextCreateSeconds: bridgeResult.context_create_ms / 1000.0,
            generationSeconds: bridgeResult.generation_ms / 1000.0,
            inferenceMode: bridgeResult.accelerated_mode == 1
                ? .accelerated
                : .safe,
            imageCacheHit: bridgeResult.cache_hit == 1,
            residentModelHit: bridgeResult.resident_model_hit == 1,
            residentContextHit: bridgeResult.resident_context_hit == 1,
            kvReuseHit: bridgeResult.kv_reuse_hit == 1,
            imageCacheBytes: UInt64(bridgeResult.cache_bytes),
            resourceGovernorState: governorState,
            resourceHeadroomBeforeMiB: headroomBeforeGovernor,
            resourceHeadroomAfterReleaseMiB: headroomAfterRelease,
            resourceReleasedResidentBeforeEncode: releasedResidentBeforeEncode,
            resourceAdjustedVision:
                visionConfig.imageMaxTokens != requestedVisionConfig.imageMaxTokens,
            resourceRequestedImageTokens: requestedVisionConfig.imageMaxTokens,
            resourceEffectiveImageTokens: visionConfig.imageMaxTokens
        )
    }

    func probeVisionOnly(
        mmprojURL: URL,
        config: VisionConfig
    ) throws -> VisionProbeMetrics {
        let vision = try config.validated()

        // Clean-room diagnostic: do NOT run mtmd_get_memory_usage first.
        // Prism's current "no_alloc" estimator still allocates backend
        // weight buffers before skipping tensor data reads, which can
        // consume hundreds of MiB and contaminate this test.
        unloadAll()

        let scoped = mmprojURL.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                mmprojURL.stopAccessingSecurityScopedResource()
            }
        }

        let attrs = try FileManager.default.attributesOfItem(
            atPath: mmprojURL.path
        )
        let sizeBytes = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let sizeMiB = Int(sizeBytes / 1_048_576)

        UserDefaults.standard.set(
            mmprojURL.lastPathComponent,
            forKey: "BonsaiLabVisionProbeFileName"
        )
        UserDefaults.standard.set(
            sizeMiB,
            forKey: "BonsaiLabVisionProbeFileSizeMiB"
        )

        let progressURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("bonsai_mtmd_probe_progress.txt")

        try? FileManager.default.createDirectory(
            at: progressURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? "-99\n".write(
            to: progressURL,
            atomically: true,
            encoding: .utf8
        )

        let before = availableHeadroomMiB()
        UserDefaults.standard.set(
            before,
            forKey: "BonsaiLabVisionProbeHeadroomBeforeMiB"
        )
        UserDefaults.standard.synchronize()

        mark("VISION_PROBE_03_MMPROJ_ONLY_BEGIN")

        let result = mmprojURL.path.withCString { modelPath in
            progressURL.path.withCString { progressPath in
                BonsaiProbeMTMD(
                    modelPath,
                    nil,
                    vision.useGPU,
                    Int32(vision.imageMaxTokens),
                    progressPath
                )
            }
        }

        let progressCode = readProbeProgress(from: progressURL)

        guard result.ok == 1 else {
            UserDefaults.standard.set(
                progressCode,
                forKey: "BonsaiLabVisionProbeProgressCode"
            )
            UserDefaults.standard.synchronize()
            mark("VISION_PROBE_03_MMPROJ_ONLY_NULL")
            throw LabError.mmprojLoadFailed
        }

        guard result.supports_vision == 1 else {
            mark("VISION_PROBE_05_CAPABILITY_FAIL")
            throw LabError.mmprojNotVision
        }

        let after = availableHeadroomMiB()
        UserDefaults.standard.set(
            after,
            forKey: "BonsaiLabVisionProbeHeadroomAfterMiB"
        )
        UserDefaults.standard.set(
            progressCode,
            forKey: "BonsaiLabVisionProbeProgressCode"
        )
        UserDefaults.standard.synchronize()

        mark("VISION_PROBE_99_PASS")
        return VisionProbeMetrics(
            fileName: mmprojURL.lastPathComponent,
            fileSizeMiB: sizeMiB,
            headroomBeforeMiB: before,
            headroomAfterMiB: after,
            progressCode: progressCode
        )
    }

    func probeVisionWithResidentModel(
        mmprojURL: URL,
        config: VisionConfig,
        linkTextModel: Bool
    ) throws -> CoexistenceProbeMetrics {
        guard let model else { throw LabError.noModel }
        let vision = try config.validated()

        unloadVision()

        // Keep the model weights resident but drop the tiny text context.
        if let context {
            mark("COEX_00_CONTEXT_RELEASE_BEGIN")
            llama_free(context)
            self.context = nil
            mark("COEX_00_CONTEXT_RELEASE_DONE")
        }

        let scoped = mmprojURL.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                mmprojURL.stopAccessingSecurityScopedResource()
            }
        }

        let attrs = try FileManager.default.attributesOfItem(
            atPath: mmprojURL.path
        )
        let sizeBytes = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let sizeMiB = Int(sizeBytes / 1_048_576)
        let mode = linkTextModel
            ? "MODEL_RESIDENT_LINKED"
            : "MODEL_RESIDENT_UNLINKED"

        let progressURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("bonsai_mtmd_coexist_progress.txt")

        try? FileManager.default.createDirectory(
            at: progressURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? "-99\n".write(
            to: progressURL,
            atomically: true,
            encoding: .utf8
        )

        let processBefore = availableHeadroomMiB()
        let metalBefore = metalSnapshotMiB()
        let systemBefore = currentSystemDiagnostics()

        UserDefaults.standard.set(mode, forKey: "BonsaiLabCoexMode")
        UserDefaults.standard.set(
            mmprojURL.lastPathComponent,
            forKey: "BonsaiLabCoexFileName"
        )
        UserDefaults.standard.set(sizeMiB, forKey: "BonsaiLabCoexFileSizeMiB")
        UserDefaults.standard.set(
            processBefore,
            forKey: "BonsaiLabCoexHeadroomBeforeMiB"
        )
        UserDefaults.standard.set(
            metalBefore.allocated,
            forKey: "BonsaiLabCoexMetalBeforeMiB"
        )
        UserDefaults.standard.set(
            metalBefore.recommended,
            forKey: "BonsaiLabCoexMetalRecommendedMiB"
        )
        UserDefaults.standard.set(
            systemBefore.physFootprintMiB,
            forKey: "BonsaiLabCoexPhysBeforeMiB"
        )
        UserDefaults.standard.set(
            systemBefore.residentMiB,
            forKey: "BonsaiLabCoexResidentBeforeMiB"
        )
        UserDefaults.standard.set(
            systemBefore.virtualMiB,
            forKey: "BonsaiLabCoexVirtualBeforeMiB"
        )
        UserDefaults.standard.set(
            Int(systemBefore.extendedVA),
            forKey: "BonsaiLabCoexExtendedVA"
        )
        UserDefaults.standard.set(
            Int(systemBefore.increasedMemoryLimit),
            forKey: "BonsaiLabCoexIncreasedMemory"
        )
        UserDefaults.standard.set(
            appliedRuntime.loadMode.rawValue,
            forKey: "BonsaiLabCoexLoadMode"
        )
        UserDefaults.standard.synchronize()

        mark(
            linkTextModel
                ? "COEX_02_LINKED_MMPROJ_BEGIN"
                : "COEX_01_UNLINKED_MMPROJ_BEGIN"
        )

        let textModel: OpaquePointer? = linkTextModel ? model : nil
        let result = mmprojURL.path.withCString { modelPath in
            progressURL.path.withCString { progressPath in
                BonsaiProbeMTMD(
                    modelPath,
                    textModel,
                    vision.useGPU,
                    Int32(vision.imageMaxTokens),
                    progressPath
                )
            }
        }

        let progressCode = readProbeProgress(from: progressURL)
        UserDefaults.standard.set(
            progressCode,
            forKey: "BonsaiLabCoexProgressCode"
        )
        UserDefaults.standard.synchronize()

        guard result.ok == 1 else {
            mark(
                linkTextModel
                    ? "COEX_02_LINKED_MMPROJ_NULL"
                    : "COEX_01_UNLINKED_MMPROJ_NULL"
            )
            self.context = try? makeContext(
                model: model,
                config: appliedRuntime
            )
            throw LabError.mmprojLoadFailed
        }

        guard result.supports_vision == 1 else {
            mark("COEX_03_CAPABILITY_FAIL")
            self.context = try? makeContext(
                model: model,
                config: appliedRuntime
            )
            throw LabError.mmprojNotVision
        }

        let processAfter = availableHeadroomMiB()
        let metalAfter = metalSnapshotMiB()

        UserDefaults.standard.set(
            processAfter,
            forKey: "BonsaiLabCoexHeadroomAfterMiB"
        )
        UserDefaults.standard.set(
            metalAfter.allocated,
            forKey: "BonsaiLabCoexMetalAfterMiB"
        )
        UserDefaults.standard.synchronize()

        // Restore text functionality after a successful diagnostic.
        self.context = try? makeContext(
            model: model,
            config: appliedRuntime
        )

        mark(
            linkTextModel
                ? "COEX_99_LINKED_PASS"
                : "COEX_99_UNLINKED_PASS"
        )

        return CoexistenceProbeMetrics(
            mode: mode,
            fileName: mmprojURL.lastPathComponent,
            fileSizeMiB: sizeMiB,
            processHeadroomBeforeMiB: processBefore,
            processHeadroomAfterMiB: processAfter,
            metalAllocatedBeforeMiB: metalBefore.allocated,
            metalAllocatedAfterMiB: metalAfter.allocated,
            metalRecommendedMiB: metalBefore.recommended,
            progressCode: progressCode
        )
    }

    func cleanupAfterRequestFailure() {
        apiVisionPrefixReuseKey = nil
        apiVisionPrefixPositions = 0
        if let context {
            llama_memory_clear(
                llama_get_memory(context),
                true
            )
        }
        mark("API_REQUEST_FAIL_CONTEXT_CLEARED")
    }

    func generateText(
        systemPrompt: String,
        userPrompt: String,
        generation: GenerationConfig,
        reasoningEffort: String? = nil,
        onDelta: (@Sendable (String) -> Void)? = nil
    ) throws -> GenerationMetrics {
        guard let context, let vocab else { throw LabError.noModel }
        let gen = try generation.validated(context: appliedRuntime.context)

        let prompt = makeSimpleChatPrompt(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            reasoningEffort: reasoningEffort
        )
        let tokens = try tokenize(prompt, vocab: vocab)

        if tokens.count + gen.maxTokens >= appliedRuntime.context {
            throw LabError.promptTooLong(tokens.count + gen.maxTokens, appliedRuntime.context)
        }

        mark("TEXT_01_BEGIN")
        apiVisionPrefixReuseKey = nil
        apiVisionPrefixPositions = 0
        llama_memory_clear(llama_get_memory(context), true)

        let sampler = makeSampler(vocab: vocab, config: gen)
        defer { llama_sampler_free(sampler) }

        let start = DispatchTime.now().uptimeNanoseconds
        try evalTextTokens(tokens, context: context, batchSize: appliedRuntime.batch)
        mark("TEXT_02_PROMPT_DONE")

        let generationStart = DispatchTime.now().uptimeNanoseconds
        let generated = try decodeGeneratedTokens(
            context: context,
            vocab: vocab,
            sampler: sampler,
            startPosition: Int32(tokens.count),
            maxTokens: gen.maxTokens,
            stagePrefix: "TEXT",
            onDelta: onDelta
        )
        let end = DispatchTime.now().uptimeNanoseconds

        guard !generated.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            mark("TEXT_90_EMPTY_OUTPUT")
            throw LabError.emptyOutput
        }

        let first = generated.firstTokenTime ?? end
        let ttft = Double(first - start) / 1_000_000_000.0
        let generationSeconds = max(
            0.000001,
            Double(end - generationStart) / 1_000_000_000.0
        )

        mark("TEXT_99_PASS")
        return GenerationMetrics(
            text: generated.text,
            generatedTokens: generated.count,
            promptTokens: tokens.count,
            effectiveMaxTokens: gen.maxTokens,
            terminationReason:
                generated.terminationReason,
            ttftSeconds: ttft,
            generationSeconds: generationSeconds,
            tokensPerSecond: Double(generated.count) / generationSeconds
        )
    }

    func generateVision(
        imageURL: URL,
        question: String,
        generation: GenerationConfig,
        onDelta: (@Sendable (String) -> Void)? = nil
    ) throws -> VisionMetrics {
        guard let context, let vocab, let visionContext else {
            throw LabError.noVision
        }
        let gen = try generation.validated(context: appliedRuntime.context)

        let imageScoped = imageURL.startAccessingSecurityScopedResource()
        defer {
            if imageScoped {
                imageURL.stopAccessingSecurityScopedResource()
            }
        }

        mark("VISION_10_IMAGE_LOAD_BEGIN")
        let wrapper = mtmd_helper_bitmap_init_from_file(
            visionContext,
            imageURL.path,
            false
        )
        guard let bitmap = wrapper.bitmap else {
            mark("VISION_10_IMAGE_LOAD_FAIL")
            throw LabError.imageLoadFailed
        }
        defer {
            mtmd_bitmap_free(bitmap)
            if let video = wrapper.video_ctx {
                mtmd_helper_video_free(video)
            }
        }
        mark("VISION_11_IMAGE_LOAD_DONE")

        llama_memory_clear(llama_get_memory(context), true)

        let marker = String(cString: mtmd_default_marker())
        let rawPrompt = makeSimpleChatPrompt(
            systemPrompt: "You are a helpful assistant.",
            userPrompt: marker + "\n" + question
        )

        guard let chunks = mtmd_input_chunks_init() else {
            throw LabError.visionTokenizeFailed(-1)
        }
        defer { mtmd_input_chunks_free(chunks) }

        var tokenizeCode: Int32 = -1
        rawPrompt.withCString { promptCString in
            var text = mtmd_input_text(
                text: promptCString,
                text_len: strlen(promptCString),
                add_special: true,
                parse_special: true
            )
            var bitmapList: [OpaquePointer?] = [bitmap]
            tokenizeCode = bitmapList.withUnsafeMutableBufferPointer { buffer in
                mtmd_tokenize(
                    visionContext,
                    chunks,
                    &text,
                    buffer.baseAddress,
                    buffer.count
                )
            }
        }

        guard tokenizeCode == 0 else {
            mark("VISION_12_TOKENIZE_FAIL_\(tokenizeCode)")
            throw LabError.visionTokenizeFailed(tokenizeCode)
        }

        let mediaTokens = Int(mtmd_helper_get_n_tokens(chunks))
        if mediaTokens + gen.maxTokens >= appliedRuntime.context {
            throw LabError.promptTooLong(
                mediaTokens + gen.maxTokens,
                appliedRuntime.context
            )
        }

        let sampler = makeSampler(vocab: vocab, config: gen)
        defer { llama_sampler_free(sampler) }

        mark("VISION_13_PREFILL_BEGIN")
        let prefillStart = DispatchTime.now().uptimeNanoseconds
        var nPast: llama_pos = 0
        let evalCode = mtmd_helper_eval_chunks(
            visionContext,
            context,
            chunks,
            0,
            0,
            Int32(appliedRuntime.batch),
            true,
            &nPast
        )
        guard evalCode == 0 else {
            mark("VISION_13_PREFILL_FAIL_\(evalCode)")
            throw LabError.visionEvalFailed(evalCode)
        }
        let prefillEnd = DispatchTime.now().uptimeNanoseconds
        mark("VISION_14_PREFILL_DONE")

        let generationStart = DispatchTime.now().uptimeNanoseconds
        let generated = try decodeGeneratedTokens(
            context: context,
            vocab: vocab,
            sampler: sampler,
            startPosition: nPast,
            maxTokens: gen.maxTokens,
            stagePrefix: "VISION",
            onDelta: onDelta
        )
        let end = DispatchTime.now().uptimeNanoseconds

        guard !generated.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            mark("VISION_90_EMPTY_OUTPUT")
            throw LabError.emptyOutput
        }

        let first = generated.firstTokenTime ?? end
        let ttft = Double(first - prefillStart) / 1_000_000_000.0
        let generationSeconds = max(
            0.000001,
            Double(end - generationStart) / 1_000_000_000.0
        )

        let base = GenerationMetrics(
            text: generated.text,
            generatedTokens: generated.count,
            promptTokens: mediaTokens,
            effectiveMaxTokens: gen.maxTokens,
            terminationReason:
                generated.terminationReason,
            ttftSeconds: ttft,
            generationSeconds: generationSeconds,
            tokensPerSecond: Double(generated.count) / generationSeconds
        )

        mark("VISION_99_PASS")
        return VisionMetrics(
            generation: base,
            mediaTokens: mediaTokens,
            visionPrefillSeconds: Double(prefillEnd - prefillStart) / 1_000_000_000.0
        )
    }

    func systemDiagnostics() -> SystemDiagnostics {
        currentSystemDiagnostics()
    }

    func apiAdmissionSnapshot() -> String {
        let system = currentSystemDiagnostics()
        let metal = metalSnapshotMiB()
        return """
        available_mib=\(system.availableMiB)
        resident_mib=\(system.residentMiB)
        phys_footprint_mib=\(system.physFootprintMiB)
        virtual_mib=\(system.virtualMiB)
        metal_allocated_mib=\(metal.allocated)
        metal_recommended_mib=\(metal.recommended)
        """
    }

    func unloadVision() {
        if let visionContext {
            mtmd_free(visionContext)
            self.visionContext = nil
        }
        if let visionVocabModel {
            llama_model_free(visionVocabModel)
            self.visionVocabModel = nil
        }
        stopMMProjScope()
    }

    func unloadAll(
        releaseStagedResident: Bool = true
    ) {
        apiVisionPrefixReuseKey = nil
        apiVisionPrefixPositions = 0
        unloadVision()

        if let context {
            llama_free(context)
            self.context = nil
        }
        if let model {
            llama_model_free(model)
            self.model = nil
        }

        vocab = nil
        stopModelScope()

        if releaseStagedResident {
            BonsaiReleaseStagedResidentModel()
            stopStagedResidentModelScope()
        }
    }

    private func makeContext(
        model: OpaquePointer,
        config: RuntimeConfig
    ) throws -> OpaquePointer {
        let validated = try config.validated()

        var params = llama_context_default_params()
        params.n_ctx = UInt32(validated.context)
        params.n_batch = UInt32(validated.batch)
        params.n_ubatch = UInt32(validated.ubatch)
        // Keep all recreated contexts on the build-40 validated shape.
        params.n_seq_max = 1
        params.n_outputs_max = 1
        params.n_outputs_max_per_seq = 1
        params.swa_full = validated.swaFull
        params.kv_unified = validated.kvUnified
        params.offload_kqv = validated.offloadKQV
        params.op_offload = validated.opOffload
        params.flash_attn_type = validated.flashAttention
            ? LLAMA_FLASH_ATTN_TYPE_ENABLED
            : LLAMA_FLASH_ATTN_TYPE_DISABLED

        let cpuCount = ProcessInfo.processInfo.processorCount
        let threads = max(1, min(6, cpuCount - 2))
        params.n_threads = Int32(threads)
        params.n_threads_batch = Int32(threads)

        guard let created = llama_init_from_model(model, params) else {
            throw LabError.contextCreateFailed
        }
        return created
    }

    private func readProbeProgress(from url: URL) -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return -999
        }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? -998
    }

    private func currentSystemDiagnostics() -> SystemDiagnostics {
        let probe = BonsaiReadSystemProbe()
        return SystemDiagnostics(
            availableMiB: Int(probe.available_bytes / 1_048_576),
            residentMiB: Int(probe.resident_bytes / 1_048_576),
            virtualMiB: Int(probe.virtual_bytes / 1_048_576),
            physFootprintMiB: Int(probe.phys_footprint_bytes / 1_048_576),
            extendedVA: provisioningEntitlementFlag(
                "com.apple.developer.kernel.extended-virtual-addressing"
            ),
            increasedMemoryLimit: provisioningEntitlementFlag(
                "com.apple.developer.kernel.increased-memory-limit"
            )
        )
    }

    private func provisioningEntitlementFlag(
        _ key: String
    ) -> Int32 {
        guard
            let url = Bundle.main.url(
                forResource: "embedded",
                withExtension: "mobileprovision"
            ),
            let data = try? Data(contentsOf: url),
            let plistStart = data.range(
                of: Data("<plist".utf8)
            )?.lowerBound,
            let plistEndRange = data.range(
                of: Data("</plist>".utf8),
                options: [],
                in: plistStart..<data.endIndex
            )
        else {
            return -1
        }

        let plistEnd = plistEndRange.upperBound
        let plistData = data.subdata(in: plistStart..<plistEnd)

        guard
            let object = try? PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil
            ),
            let root = object as? [String: Any],
            let entitlements = root["Entitlements"] as? [String: Any]
        else {
            return -1
        }

        if let value = entitlements[key] as? Bool {
            return value ? 1 : 0
        }
        if let value = entitlements[key] as? NSNumber {
            return value.boolValue ? 1 : 0
        }
        return 0
    }

    private func persistSystemDiagnostics(prefix: String) {
        let d = currentSystemDiagnostics()
        let defaults = UserDefaults.standard
        defaults.set(d.availableMiB, forKey: prefix + "AvailableMiB")
        defaults.set(d.residentMiB, forKey: prefix + "ResidentMiB")
        defaults.set(d.virtualMiB, forKey: prefix + "VirtualMiB")
        defaults.set(d.physFootprintMiB, forKey: prefix + "PhysMiB")
        defaults.set(Int(d.extendedVA), forKey: prefix + "ExtendedVA")
        defaults.set(
            Int(d.increasedMemoryLimit),
            forKey: prefix + "IncreasedMemory"
        )
        defaults.synchronize()
    }

    private func metalSnapshotMiB() -> (
        allocated: Int,
        recommended: Int
    ) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return (0, 0)
        }

        let allocated = Int(device.currentAllocatedSize / 1_048_576)
        let recommended = Int(
            device.recommendedMaxWorkingSetSize / 1_048_576
        )
        return (allocated, recommended)
    }

    private func availableHeadroomMiB() -> Int {
        Int(os_proc_available_memory() / 1_048_576)
    }

    private func stopModelScope() {
        if hasModelScope, let modelScopedURL {
            modelScopedURL.stopAccessingSecurityScopedResource()
        }
        hasModelScope = false
        modelScopedURL = nil
    }

    private func stopStagedResidentModelScope() {
        if
            hasStagedResidentModelScope,
            let stagedResidentModelScopedURL
        {
            stagedResidentModelScopedURL
                .stopAccessingSecurityScopedResource()
        }

        hasStagedResidentModelScope = false
        stagedResidentModelScopedURL = nil
    }

    private func stopMMProjScope() {
        if hasMMProjScope, let mmprojScopedURL {
            mmprojScopedURL.stopAccessingSecurityScopedResource()
        }
        hasMMProjScope = false
        mmprojScopedURL = nil
    }

    private func makeSimpleChatPrompt(
        systemPrompt: String,
        userPrompt: String,
        reasoningEffort: String? = nil
    ) -> String {
        let system = systemPrompt.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        // Ternary-Bonsai / Qwen3.8 chat-template parity:
        // enable_thinking=false does NOT rely on an instruction.
        // It pre-fills an already-closed empty think block before
        // generation, which switches the model into direct-answer mode.
        let assistantPrefix: String
        if reasoningEffort == "none" {
            assistantPrefix =
                "<|im_start|>assistant\n"
                + "<think>\n\n</think>\n\n"
        } else {
            assistantPrefix = "<|im_start|>assistant\n"
        }

        if system.isEmpty {
            return "<|im_start|>user\n"
                + userPrompt
                + "<|im_end|>\n"
                + assistantPrefix
        }

        return "<|im_start|>system\n"
            + system
            + "<|im_end|>\n<|im_start|>user\n"
            + userPrompt
            + "<|im_end|>\n"
            + assistantPrefix
    }

    private func tokenize(
        _ text: String,
        vocab: OpaquePointer
    ) throws -> [llama_token] {
        let utf8Count = text.utf8.count
        var capacity = max(64, utf8Count + 32)

        while capacity < 1_000_000 {
            let pointer = UnsafeMutablePointer<llama_token>.allocate(capacity: capacity)
            let count = llama_tokenize(
                vocab,
                text,
                Int32(utf8Count),
                pointer,
                Int32(capacity),
                true,
                true
            )

            if count >= 0 {
                let result = Array(
                    UnsafeBufferPointer(start: pointer, count: Int(count))
                )
                pointer.deallocate()
                return result
            }

            pointer.deallocate()
            capacity = Int(-count)
        }

        throw LabError.tokenizerFailed
    }

    private func evalTextTokens(
        _ tokens: [llama_token],
        context: OpaquePointer,
        batchSize: Int
    ) throws {
        var position: Int32 = 0
        var offset = 0

        while offset < tokens.count {
            let count = min(batchSize, tokens.count - offset)
            var batch = llama_batch_init(Int32(count), 0, 1)
            batch.n_tokens = 0

            for localIndex in 0..<count {
                let tokenIndex = offset + localIndex
                let isLast = tokenIndex == tokens.count - 1
                addToken(
                    &batch,
                    token: tokens[tokenIndex],
                    position: position,
                    logits: isLast
                )
                position += 1
            }

            let code = llama_decode(context, batch)
            llama_batch_free(batch)

            if code != 0 {
                throw LabError.decodeFailed(code)
            }
            offset += count
        }
    }

    private func makeSampler(
        vocab: OpaquePointer,
        config: GenerationConfig
    ) -> UnsafeMutablePointer<llama_sampler> {
        let params = llama_sampler_chain_default_params()
        let sampler = llama_sampler_chain_init(params)!

        if config.repeatPenalty != 1.0 {
            llama_sampler_chain_add(
                sampler,
                llama_sampler_init_penalties(
                    llama_vocab_n_tokens(vocab),
                    64,
                    Float(config.repeatPenalty),
                    0,
                    0
                )
            )
        }

        llama_sampler_chain_add(
            sampler,
            llama_sampler_init_top_k(Int32(config.topK))
        )
        llama_sampler_chain_add(
            sampler,
            llama_sampler_init_top_p(Float(config.topP), 1)
        )

        if config.minP > 0 {
            llama_sampler_chain_add(
                sampler,
                llama_sampler_init_min_p(Float(config.minP), 1)
            )
        }

        if config.temperature > 0 {
            llama_sampler_chain_add(
                sampler,
                llama_sampler_init_temp(Float(config.temperature))
            )
            llama_sampler_chain_add(
                sampler,
                llama_sampler_init_dist(UInt32(config.seed))
            )
        } else {
            llama_sampler_chain_add(
                sampler,
                llama_sampler_init_greedy()
            )
        }

        return sampler
    }

    private func decodeGeneratedTokens(
        context: OpaquePointer,
        vocab: OpaquePointer,
        sampler: UnsafeMutablePointer<llama_sampler>,
        startPosition: Int32,
        maxTokens: Int,
        stagePrefix: String,
        onDelta: (@Sendable (String) -> Void)? = nil
    ) throws -> (
        text: String,
        count: Int,
        firstTokenTime: UInt64?,
        terminationReason: GenerationTerminationReason
    ) {
        var output = ""
        var pending: [CChar] = []
        var position = startPosition
        var generated = 0
        var firstTokenTime: UInt64?
        var terminationReason: GenerationTerminationReason = .length

        while generated < maxTokens {
            let token = llama_sampler_sample(sampler, context, -1)

            if llama_vocab_is_eog(vocab, token) {
                terminationReason = .eog
                break
            }

            if firstTokenTime == nil {
                firstTokenTime = DispatchTime.now().uptimeNanoseconds
                mark("\(stagePrefix)_20_FIRST_TOKEN")
            }

            pending.append(contentsOf: tokenPiece(vocab: vocab, token: token))
            if let valid = String(validatingUTF8: pending + [0]) {
                output += valid
                pending.removeAll(keepingCapacity: true)
                if !valid.isEmpty { onDelta?(valid) }
            }

            var batch = llama_batch_init(1, 0, 1)
            batch.n_tokens = 0
            addToken(
                &batch,
                token: token,
                position: position,
                logits: true
            )

            let code = llama_decode(context, batch)
            llama_batch_free(batch)

            if code != 0 {
                mark("\(stagePrefix)_30_DECODE_FAIL_\(code)")
                throw LabError.decodeFailed(code)
            }

            position += 1
            generated += 1
        }

        if !pending.isEmpty {
            let tail = String(
                decoding: pending.map { UInt8(bitPattern: $0) },
                as: UTF8.self
            )
            output += tail
            if !tail.isEmpty { onDelta?(tail) }
        }

        return (
            output,
            generated,
            firstTokenTime,
            terminationReason
        )
    }

    private func tokenPiece(
        vocab: OpaquePointer,
        token: llama_token
    ) -> [CChar] {
        var small = [CChar](repeating: 0, count: 32)
        let count = llama_token_to_piece(
            vocab,
            token,
            &small,
            Int32(small.count),
            0,
            true
        )

        if count >= 0 {
            return Array(small.prefix(Int(count)))
        }

        var large = [CChar](repeating: 0, count: Int(-count))
        let retry = llama_token_to_piece(
            vocab,
            token,
            &large,
            Int32(large.count),
            0,
            true
        )

        if retry < 0 {
            return []
        }
        return Array(large.prefix(Int(retry)))
    }

    private func addToken(
        _ batch: inout llama_batch,
        token: llama_token,
        position: llama_pos,
        logits: Bool
    ) {
        let index = Int(batch.n_tokens)
        batch.token[index] = token
        batch.pos[index] = position
        batch.n_seq_id[index] = 1
        batch.seq_id[index]![0] = 0
        batch.logits[index] = logits ? 1 : 0
        batch.n_tokens += 1
    }
}
