import SwiftUI
import UniformTypeIdentifiers
import UIKit

private enum RC1232PerformanceDiagnostics {
    static let defaultsKey =
        "BonsaiRC1232LastAPIRequestMetrics"
    static let longRunHistoryDefaultsKey =
        "BonsaiRC1233LongRunRequestHistory"

    private static let stateQueue = DispatchQueue(
        label: "local.bonsai.rc1233.long-run-diagnostics"
    )
    private static var sessionRequestOrdinal = 0
    private static let historyLimit = 32

    static func beginSession() {
        stateQueue.sync {
            sessionRequestOrdinal = 0
            UserDefaults.standard.removeObject(
                forKey: longRunHistoryDefaultsKey
            )
        }
    }

    static func nextRequestOrdinal() -> Int {
        stateQueue.sync {
            sessionRequestOrdinal += 1
            return sessionRequestOrdinal
        }
    }

    private static func resourceValue(
        _ key: String,
        from snapshot: String
    ) -> String {
        for line in snapshot.split(separator: "\n") {
            let prefix = key + "="
            if line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count))
            }
        }
        return "-1"
    }

    private static func resourceLines(
        from snapshot: String
    ) -> [String] {
        [
            "available_mib="
                + resourceValue("available_mib", from: snapshot),
            "resident_mib="
                + resourceValue("resident_mib", from: snapshot),
            "phys_footprint_mib="
                + resourceValue("phys_footprint_mib", from: snapshot),
            "virtual_mib="
                + resourceValue("virtual_mib", from: snapshot),
            "metal_allocated_mib="
                + resourceValue("metal_allocated_mib", from: snapshot),
            "metal_recommended_mib="
                + resourceValue("metal_recommended_mib", from: snapshot),
        ]
    }

    private static func appendLongRunHistory(
        _ fields: [String]
    ) {
        stateQueue.sync {
            let defaults = UserDefaults.standard
            var rows =
                defaults.string(
                    forKey: longRunHistoryDefaultsKey
                )?
                .split(separator: "\n")
                .map(String.init)
                ?? []
            rows.append(fields.joined(separator: " "))
            if rows.count > historyLimit {
                rows = Array(rows.suffix(historyLimit))
            }
            defaults.set(
                rows.joined(separator: "\n"),
                forKey: longRunHistoryDefaultsKey
            )
        }
    }

    static func now() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    static func milliseconds(
        from start: UInt64,
        to end: UInt64
    ) -> Double {
        guard end >= start else { return 0 }
        return Double(end - start) / 1_000_000.0
    }

    static func persist(_ lines: [String]) {
        UserDefaults.standard.set(
            lines.joined(separator: "\n"),
            forKey: defaultsKey
        )
    }

    static func formatMilliseconds(
        _ value: Double
    ) -> String {
        String(format: "%.3f", value)
    }

    static func persistFailure(
        requestID: String,
        requestOrdinal: Int,
        route: String,
        stream: Bool,
        requestStart: UInt64,
        lastStage: String
    ) {
        let end = now()
        let totalMilliseconds =
            formatMilliseconds(
                milliseconds(
                    from: requestStart,
                    to: end
                )
            )
        persist([
            "request_id=\(requestID)",
            "request_ordinal=\(requestOrdinal)",
            "route=\(route)",
            "stream=\(stream)",
            "result=failed_or_interrupted",
            "total_ms=" + totalMilliseconds,
            "last_stage=\(lastStage)",
        ])
        appendLongRunHistory([
            "ordinal=\(requestOrdinal)",
            "route=\(route)",
            "result=failed_or_interrupted",
            "total_ms=\(totalMilliseconds)",
            "last_stage=\(lastStage)",
        ])
    }

    static func persistVisionSuccess(
        requestID: String,
        requestOrdinal: Int,
        stream: Bool,
        packet: MLXVisionEmbeddingPacket,
        metrics: VisionMetrics,
        imageOrdering: OpenAIImageOrdering,
        prefixReuseEnabled: Bool,
        resourceSnapshot: String,
        imageWriteStart: UInt64,
        imageWriteEnd: UInt64,
        visionEncodeStart: UInt64,
        visionEncodeEnd: UInt64,
        cacheWriteStart: UInt64,
        cacheWriteEnd: UInt64,
        requestStart: UInt64,
        requestEnd: UInt64
    ) {
        let totalMilliseconds =
            formatMilliseconds(
                milliseconds(
                    from: requestStart,
                    to: requestEnd
                )
            )
        let visionEncodeMilliseconds =
            formatMilliseconds(
                milliseconds(
                    from: visionEncodeStart,
                    to: visionEncodeEnd
                )
            )
        let prefillMilliseconds =
            formatMilliseconds(
                metrics.visionPrefillSeconds * 1_000
            )
        let suffixPrefillMilliseconds =
            formatMilliseconds(
                metrics.suffixPrefillSeconds * 1_000
            )
        let decodeMilliseconds =
            formatMilliseconds(
                metrics.generation.generationSeconds * 1_000
            )
        let tokensPerSecond =
            String(
                format: "%.3f",
                metrics.generation.tokensPerSecond
            )
        let resources = resourceLines(from: resourceSnapshot)

        persist([
            "request_id=\(requestID)",
            "request_ordinal=\(requestOrdinal)",
            "route=vision",
            "stream=\(stream)",
            "result=success",
            "image_write_ms="
                + formatMilliseconds(
                    milliseconds(
                        from: imageWriteStart,
                        to: imageWriteEnd
                    )
                ),
            "vision_encode_ms=" + visionEncodeMilliseconds,
            "vision_encode_reported_ms="
                + formatMilliseconds(
                    packet.metrics.encodeSeconds * 1_000
                ),
            "cache_write_ms="
                + formatMilliseconds(
                    milliseconds(
                        from: cacheWriteStart,
                        to: cacheWriteEnd
                    )
                ),
            "prefill_ms=" + prefillMilliseconds,
            "decode_ms=" + decodeMilliseconds,
            "tokens_per_second=" + tokensPerSecond,
            "prompt_tokens=\(metrics.generation.promptTokens)",
            "completion_tokens=\(metrics.generation.generatedTokens)",
            "visual_rows=\(packet.metrics.outputTokens)",
            "projection_dim=\(packet.metrics.outputDimension)",
            "grid=\(packet.gridY)x\(packet.gridX)",
            "n_pos=\(max(packet.gridX, packet.gridY))",
            "image_ordering=\(imageOrdering.rawValue)",
            "prefix_reuse_enabled=\(prefixReuseEnabled)",
            "prefix_reuse_hit=\(metrics.prefixReuseHit)",
            "prefix_retained=\(metrics.prefixRetainedForReuse)",
            "prefix_positions=\(metrics.prefixPositions)",
            "prefix_text_ms="
                + formatMilliseconds(
                    metrics.prefixTextSeconds * 1_000
                ),
            "image_prefill_ms="
                + formatMilliseconds(
                    metrics.imagePrefillSeconds * 1_000
                ),
            "suffix_prefill_ms=" + suffixPrefillMilliseconds,
            "cache_reuse="
                + (metrics.prefixReuseHit
                    ? "vision_prefix_kv_hit"
                    : "vision_prefix_kv_miss"),
            "total_ms=" + totalMilliseconds,
        ] + resources)

        appendLongRunHistory([
            "ordinal=\(requestOrdinal)",
            "route=vision",
            "result=success",
            "hit=\(metrics.prefixReuseHit)",
            "retained=\(metrics.prefixRetainedForReuse)",
            "total_ms=\(totalMilliseconds)",
            "prefill_ms=\(prefillMilliseconds)",
            "suffix_prefill_ms=\(suffixPrefillMilliseconds)",
            "decode_ms=\(decodeMilliseconds)",
            "tokens_per_second=\(tokensPerSecond)",
            "vision_encode_ms=\(visionEncodeMilliseconds)",
            "available_mib="
                + resourceValue(
                    "available_mib",
                    from: resourceSnapshot
                ),
            "resident_mib="
                + resourceValue(
                    "resident_mib",
                    from: resourceSnapshot
                ),
            "phys_footprint_mib="
                + resourceValue(
                    "phys_footprint_mib",
                    from: resourceSnapshot
                ),
            "virtual_mib="
                + resourceValue(
                    "virtual_mib",
                    from: resourceSnapshot
                ),
            "metal_allocated_mib="
                + resourceValue(
                    "metal_allocated_mib",
                    from: resourceSnapshot
                ),
            "metal_recommended_mib="
                + resourceValue(
                    "metal_recommended_mib",
                    from: resourceSnapshot
                ),
        ])
    }

    static func persistTextSuccess(
        requestID: String,
        requestOrdinal: Int,
        stream: Bool,
        metrics: GenerationMetrics,
        resourceSnapshot: String,
        textGenerationStart: UInt64,
        textGenerationEnd: UInt64,
        requestStart: UInt64
    ) {
        let totalMilliseconds =
            formatMilliseconds(
                milliseconds(
                    from: requestStart,
                    to: textGenerationEnd
                )
            )
        let decodeMilliseconds =
            formatMilliseconds(
                metrics.generationSeconds * 1_000
            )
        let tokensPerSecond =
            String(
                format: "%.3f",
                metrics.tokensPerSecond
            )
        let resources = resourceLines(from: resourceSnapshot)

        persist([
            "request_id=\(requestID)",
            "request_ordinal=\(requestOrdinal)",
            "route=text",
            "stream=\(stream)",
            "result=success",
            "text_generation_ms="
                + formatMilliseconds(
                    milliseconds(
                        from: textGenerationStart,
                        to: textGenerationEnd
                    )
                ),
            "ttft_ms="
                + formatMilliseconds(
                    metrics.ttftSeconds * 1_000
                ),
            "decode_ms=" + decodeMilliseconds,
            "tokens_per_second=" + tokensPerSecond,
            "prompt_tokens=\(metrics.promptTokens)",
            "completion_tokens=\(metrics.generatedTokens)",
            "total_ms=" + totalMilliseconds,
        ] + resources)

        appendLongRunHistory([
            "ordinal=\(requestOrdinal)",
            "route=text",
            "result=success",
            "total_ms=\(totalMilliseconds)",
            "decode_ms=\(decodeMilliseconds)",
            "tokens_per_second=\(tokensPerSecond)",
            "available_mib="
                + resourceValue(
                    "available_mib",
                    from: resourceSnapshot
                ),
            "resident_mib="
                + resourceValue(
                    "resident_mib",
                    from: resourceSnapshot
                ),
            "phys_footprint_mib="
                + resourceValue(
                    "phys_footprint_mib",
                    from: resourceSnapshot
                ),
            "virtual_mib="
                + resourceValue(
                    "virtual_mib",
                    from: resourceSnapshot
                ),
            "metal_allocated_mib="
                + resourceValue(
                    "metal_allocated_mib",
                    from: resourceSnapshot
                ),
            "metal_recommended_mib="
                + resourceValue(
                    "metal_recommended_mib",
                    from: resourceSnapshot
                ),
        ])
    }

    static func visionSummary(
        packet: MLXVisionEmbeddingPacket,
        imageOrdering: OpenAIImageOrdering,
        metrics: VisionMetrics
    ) -> String {
        packet.metrics.summary
            + "\nAPI image ordering: "
            + imageOrdering.rawValue
            + "\n27B prefill: "
            + String(
                format: "%.3f s",
                metrics.visionPrefillSeconds
            )
            + "\nPrefix reuse: "
            + (metrics.prefixReuseHit ? "HIT" : "MISS")
            + " · retained="
            + String(metrics.prefixRetainedForReuse)
            + "\nPrefill split: prefix="
            + String(
                format: "%.3f s",
                metrics.prefixTextSeconds
            )
            + " · image="
            + String(
                format: "%.3f s",
                metrics.imagePrefillSeconds
            )
            + " · suffix="
            + String(
                format: "%.3f s",
                metrics.suffixPrefillSeconds
            )
    }
}

struct ProductionView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let engine = BonsaiEngine()
    @StateObject private var apiServer = LocalOpenAIServer()

    @State private var modelURL: URL?
    @State private var mmprojURL: URL?
    @State private var imageURL: URL?
    @State private var mlxVisionWeightsURL: URL?

    @State private var modelName = "未选择"
    @State private var mmprojName = "未选择"
    @State private var imageName = "未选择"
    @State private var mlxVisionWeightsName = "未选择"

    @State private var quality = VisionQuality.standard
    @State private var answerLength = AnswerLengthPreset.standard
    @State private var question = "请描述这张图片的主要内容。"
    @State private var inferenceMode = VisionInferenceMode.accelerated
    @AppStorage("BonsaiRC1232VisionPrefixKVReuseEnabled")
    private var visionPrefixKVReuseEnabled = false

    @State private var output = ""
    @State private var status = "准备就绪"
    @State private var detail = ""
    @State private var busy = false
    @State private var usedFallback = false
    @State private var latestMetrics: StagedVisionMetrics?

    @State private var showModelImporter = false
    @State private var showMMProjImporter = false
    @State private var showImageImporter = false
    @State private var showMLXVisionImporter = false
    @State private var showAdvanced = false
    @State private var certification: [CertificationResult] = []
    @State private var warmSessionSummary = ""
    @State private var warmSessionPass: Bool?
    @State private var mlxVisionSummary = ""
    @State private var diagnosticSnapshot = ""
    private let mlxVisionSidecar = MLXVisionSidecar()

    private var runtime: RuntimeConfig {
        var value = RuntimeConfig.safe
        value.context = 256
        value.batch = 16
        value.ubatch = 16
        value.gpuLayers = 99
        value.flashAttention = true
        value.offloadKQV = true
        value.opOffload = true
        value.disableMetalTensorAPI = true
        value.kvUnified = true
        value.loadMode = .mmap
        return value
    }

    private var vision: VisionConfig {
        quality.preset.config
    }

    private var generation: GenerationConfig {
        var value = GenerationConfig()
        value.maxTokens = answerLength.maxTokens
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Bonsai 27B")
                                .font(.title2.bold())
                            Text("本地 · 离线 · Vision")
                                .foregroundStyle(.secondary)
                            Text("1.0 · RC1.23.1 OpenAI Multimodal API")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if busy {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }

                    LabeledContent("状态", value: status)

                    if usedFallback {
                        Label(
                            "本次已自动使用兼容回退，无需手动调参。",
                            systemImage: "arrow.uturn.backward.circle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
                }

                Section("模型") {
                    fileRow(
                        title: "主模型",
                        value: modelName,
                        actionTitle: "选择 27B GGUF"
                    ) {
                        showModelImporter = true
                    }
                    .fileImporter(
                        isPresented: $showModelImporter,
                        allowedContentTypes: [ggufType],
                        allowsMultipleSelection: false
                    ) { result in
                        handleImport(result, kind: .model)
                    }

                    fileRow(
                        title: "视觉模型",
                        value: mmprojName,
                        actionTitle: "选择 Q8 mmproj"
                    ) {
                        showMMProjImporter = true
                    }
                    .fileImporter(
                        isPresented: $showMMProjImporter,
                        allowedContentTypes: [ggufType],
                        allowsMultipleSelection: false
                    ) { result in
                        handleImport(result, kind: .mmproj)
                    }
                }

                Section("图片") {
                    fileRow(
                        title: "图片",
                        value: imageName,
                        actionTitle: "选择图片"
                    ) {
                        showImageImporter = true
                    }
                    .fileImporter(
                        isPresented: $showImageImporter,
                        allowedContentTypes: [.image],
                        allowsMultipleSelection: false
                    ) { result in
                        handleImport(result, kind: .image)
                    }

                    Picker("视觉质量", selection: $quality) {
                        ForEach(VisionQuality.allCases) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(quality.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("提问") {
                    TextField(
                        "关于图片的问题",
                        text: $question,
                        axis: .vertical
                    )
                    .lineLimit(2...8)

                    Picker("回答长度", selection: $answerLength) {
                        ForEach(AnswerLengthPreset.allCases) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        runProductVision()
                    } label: {
                        Label(
                            busy ? "正在处理…" : "发送",
                            systemImage: "paperplane.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        busy ||
                        modelURL == nil ||
                        mmprojURL == nil ||
                        imageURL == nil ||
                        question.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }

                Section("回答") {
                    if output.isEmpty {
                        Text("选择模型与图片后即可开始。")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(output)
                            .textSelection(.enabled)
                    }

                    if let metrics = latestMetrics {
                        HStack {
                            Label(
                                String(
                                    format: "%.2f tok/s",
                                    metrics.tokensPerSecond
                                ),
                                systemImage: "speedometer"
                            )
                            Spacer()
                            Text(
                                "\(metrics.generatedTokens) tokens · "
                                + String(
                                    format: "%.1f s",
                                    metrics.generationSeconds
                                )
                            )
                            .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                    }
                }

                Section("局域网 OpenAI API") {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(apiServer.isRunning ? "服务运行中" : "服务已停止")
                                .font(.headline)
                            Text(
                                apiServer.isRunning
                                    ? apiServer.baseURL
                                    : "启动后可由同一局域网内的设备调用"
                            )
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        }
                        Spacer()
                        Circle()
                            .fill(apiServer.isRunning ? .green : .secondary)
                            .frame(width: 10, height: 10)
                    }

                    if apiServer.isRunning {
                        LabeledContent(
                            "Model",
                            value: apiServer.modelID
                        )
                        LabeledContent(
                            "API Key",
                            value: apiServer.apiKey
                        )
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        LabeledContent(
                            "请求数",
                            value: "\(apiServer.requestCount)"
                        )

                        Text(
                            "兼容 /v1/models、/v1/models/{id} 与 /v1/chat/completions；支持 max_completion_tokens、stream=true 真 SSE 与 stream_options.include_usage。RC1.23.1 单图请求使用 data:image/png|jpeg;base64,...，并直接复用已验证的 MLX Hard Graph-Cut → Live Vision Injection 路径；不再要求 API 图片请求初始化 mmproj 或重启 App。"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                        Button("停止 API") {
                            apiServer.stop()
                            Task {
                                await engine.unloadAll()
                            }
                        }
                        .foregroundStyle(.red)

                        Button("复制 API 配置") {
                            copyAPIConfig()
                        }

                        Button("重新生成 API Key") {
                            apiServer.regenerateKey()
                        }
                    } else {
                        Button("启动 OpenAI API") {
                            startAPIServer()
                        }
                        .disabled(
                            busy ||
                            modelURL == nil
                        )
                    }

                    if !apiServer.lastError.isEmpty {
                        Text(apiServer.lastError)
                            .font(.caption.monospaced())
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }

                Section {
                    DisclosureGroup(
                        "高级与诊断",
                        isExpanded: $showAdvanced
                    ) {
                        Picker("推理模式", selection: $inferenceMode) {
                            ForEach(VisionInferenceMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        LabeledContent(
                            "实际配置",
                            value:
                                "\(vision.contextTokens) ctx · "
                                + "\(vision.imageMaxTokens) image tokens"
                        )
                        LabeledContent(
                            "资源保护",
                            value: "自动"
                        )

                        Toggle(
                            "实验：Vision Prefix KV Reuse",
                            isOn:
                                $visionPrefixKVReuseEnabled
                        )
                        Text(
                            visionPrefixKVReuseEnabled
                                ? "RC1.23.2 实验路径已启用：同图 + 同 system prompt 时尝试保留 prefix+image KV；partial trim 不受支持时会自动清空并回退。"
                                : "默认关闭。用于与 RC1.23.1 baseline 做受控 A/B；不会改变 BVCACHE1 或 Vision Tower。"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                        Text(
                            "缓存命中时保持 warm session；新图且可用内存偏低时优先释放常驻状态，必要时才自动降低视觉档位。设备认证不会启用该策略。"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("完整诊断快照")
                                .font(.headline)

                            Button("刷新并复制完整诊断") {
                                let snapshot =
                                    buildDiagnosticSnapshot()
                                diagnosticSnapshot = snapshot
                                UIPasteboard.general.string =
                                    snapshot
                            }
                            .buttonStyle(.borderedProminent)

                            Text(
                                "一次收集 API、模型、Vision、阶段、内存与最近一次 API Vision Metrics；不包含 API Key、原始图片、base64 或 prompt 正文。"
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                            if !diagnosticSnapshot.isEmpty {
                                Text(diagnosticSnapshot)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("MLX Vision Sidecar Probe")
                                .font(.headline)

                            LabeledContent(
                                "Vision Tower",
                                value: mlxVisionWeightsName
                            )
                            .lineLimit(1)

                            Button("选择 vision_tower.safetensors") {
                                showMLXVisionImporter = true
                            }
                            .fileImporter(
                                isPresented: $showMLXVisionImporter,
                                allowedContentTypes: [safetensorsType],
                                allowsMultipleSelection: false
                            ) { result in
                                handleImport(
                                    result,
                                    kind: .mlxVision
                                )
                            }

                            Button(
                                "运行 MLX Hard Graph-Cut Vision Probe"
                            ) {
                                runMLXVisionProbe()
                            }
                            .disabled(
                                busy
                                || !apiServer.isRunning
                                || mlxVisionWeightsURL == nil
                                || imageURL == nil
                            )

                            Button(
                                "运行 Live Vision Injection"
                            ) {
                                runLiveVisionInjection()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                busy
                                || !apiServer.isRunning
                                || modelURL == nil
                                || mlxVisionWeightsURL == nil
                                || imageURL == nil
                                || question
                                    .trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    )
                                    .isEmpty
                            )

                            Text(
                                "RC1.23.0 保留 RC1.22.5 Hard Graph-Cut 基线；先启动 OpenAI API 让 27B + Text Context 常驻，再把 MLX 的 projected embeddings 直接写入 BVCACHE1 并注入现有 llama context。Live 路径不会初始化 mmproj。"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if !mlxVisionSummary.isEmpty {
                                Text(mlxVisionSummary)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                        }

                        Button("运行一键设备认证") {
                            runCertification()
                        }
                        .disabled(
                            busy ||
                            modelURL == nil ||
                            mmprojURL == nil ||
                            imageURL == nil
                        )

                        if !certification.isEmpty {
                            ForEach(certification) { row in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(row.quality.label)
                                        Spacer()
                                        Text(row.pass ? "PASS" : "FAIL")
                                            .foregroundStyle(
                                                row.pass ? .green : .red
                                            )
                                    }
                                    Text(row.summary)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if !warmSessionSummary.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text("连续问答 / KV")
                                    Spacer()
                                    Text(
                                        warmSessionPass == true
                                            ? "PASS"
                                            : "FAIL"
                                    )
                                    .foregroundStyle(
                                        warmSessionPass == true
                                            ? .green
                                            : .red
                                    )
                                }
                                Text(warmSessionSummary)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !detail.isEmpty {
                            Text(detail)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }

                        NavigationLink("Developer Diagnostics") {
                            ContentView()
                        }
                    }
                }
            }
            .navigationTitle("Bonsai")
            .onAppear {
                recoverPreviousFailureHint()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .background {
                    apiServer.stop()
                    Task {
                        await engine.unloadAll()
                        await MainActor.run {
                            status = "已进入后台，已释放常驻模型并停止 API"
                            latestMetrics = nil
                        }
                    }
                }
            }
        }
    }

    private enum ImportKind {
        case model
        case mmproj
        case image
        case mlxVision
    }

    private var ggufType: UTType {
        UTType(
            filenameExtension: "gguf",
            conformingTo: .data
        )!
    }

    private var safetensorsType: UTType {
        UTType(
            filenameExtension: "safetensors",
            conformingTo: .data
        )!
    }

    private func fileRow(
        title: String,
        value: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(title, value: value)
                .lineLimit(1)
            Button(actionTitle, action: action)
                .disabled(busy)
        }
    }

    private func handleImport(
        _ result: Result<[URL], Error>,
        kind: ImportKind
    ) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            switch kind {
            case .model:
                if apiServer.isRunning { apiServer.stop() }
                Task { await engine.unloadAll() }
                modelURL = url
                modelName = url.lastPathComponent
            case .mmproj:
                if apiServer.isRunning { apiServer.stop() }
                Task { await engine.unloadAll() }
                mmprojURL = url
                mmprojName = url.lastPathComponent
            case .image:
                imageURL = url
                imageName = url.lastPathComponent
            case .mlxVision:
                mlxVisionWeightsURL = url
                mlxVisionWeightsName = url.lastPathComponent
                mlxVisionSummary = ""
            }
            status = "准备就绪"
            detail = ""
        case .failure(let error):
            status = "文件选择失败"
            detail = error.localizedDescription
        }
    }

    private func runMLXVisionProbe() {
        guard
            let weightsURL = mlxVisionWeightsURL,
            let imageURL
        else {
            return
        }

        busy = true
        status = "正在运行 MLX Vision Sidecar…"
        mlxVisionSummary = ""

        Task {
            do {
                let metrics =
                    try await mlxVisionSidecar.probe(
                        weightsURL: weightsURL,
                        imageURL: imageURL
                    )

                await MainActor.run {
                    busy = false
                    status = "MLX Vision Sidecar PASS"
                    mlxVisionSummary = metrics.summary
                    detail = metrics.summary
                }
            } catch {
                await MainActor.run {
                    busy = false
                    status = "MLX Vision Sidecar FAIL"
                    mlxVisionSummary =
                        error.localizedDescription
                    detail =
                        error.localizedDescription
                }
            }
        }
    }

    private func runLiveVisionInjection() {
        guard
            let modelURL,
            let weightsURL = mlxVisionWeightsURL,
            let imageURL
        else {
            return
        }

        guard apiServer.isRunning else {
            status = "请先启动 OpenAI API"
            detail =
                "Live Injection 需要冻结的 27B "
                + "+ Text Context 已经常驻。"
            return
        }

        busy = true
        output = ""
        status = "MLX 正在编码并注入 27B…"
        detail = ""

        Task {
            do {
                let packet =
                    try await mlxVisionSidecar
                        .encodeForInjection(
                            weightsURL: weightsURL,
                            imageURL: imageURL
                        )

                let imageMaxTokens =
                    VisionConfig.low512.imageMaxTokens

                let cacheURL =
                    try await engine
                        .writeMLXProjectedVisionCache(
                            modelURL: modelURL,
                            weightsURL: weightsURL,
                            imageURL: imageURL,
                            embeddingData:
                                packet.float32Embeddings,
                            nTokens:
                                packet.metrics.outputTokens,
                            projectionDimension:
                                packet.metrics.outputDimension,
                            gridX: packet.gridX,
                            gridY: packet.gridY,
                            imageMaxTokens:
                                imageMaxTokens
                        )

                var gen = generation
                gen.maxTokens = min(
                    gen.maxTokens,
                    128
                )

                let metrics =
                    try await engine.generateCachedVision(
                        cacheURL: cacheURL,
                        imageMaxTokens: imageMaxTokens,
                        systemPrompt:
                            "You are a helpful assistant.",
                        question: question,
                        generation: gen,
                        reasoningEffort: "none",
                        onDelta: { delta in
                            Task { @MainActor in
                                output += delta
                            }
                        }
                    )

                await MainActor.run {
                    busy = false
                    output = metrics.generation.text
                    status = "Live Vision Injection PASS"
                    detail =
                        packet.metrics.summary
                        + "\nGrid: "
                        + "\(packet.gridY)x\(packet.gridX)"
                        + " · n_pos="
                        + "\(max(packet.gridX, packet.gridY))"
                        + "\n27B prefill: "
                        + String(
                            format: "%.3f s",
                            metrics.visionPrefillSeconds
                        )
                        + " · "
                        + String(
                            format: "%.2f tok/s",
                            metrics.generation.tokensPerSecond
                        )
                }
            } catch {
                await MainActor.run {
                    busy = false
                    status = "Live Vision Injection FAIL"
                    detail = error.localizedDescription
                }
            }
        }
    }

    private func runProductVision() {
        guard
            let modelURL,
            let mmprojURL,
            let imageURL
        else {
            return
        }

        busy = true
        output = ""
        latestMetrics = nil
        usedFallback = false
        status = "正在理解图片…"
        detail = ""

        Task {
            let primaryMode = inferenceMode
            do {
                let metrics = try await engine.runStagedVision(
                    modelURL: modelURL,
                    mmprojURL: mmprojURL,
                    imageURL: imageURL,
                    question: question,
                    runtime: runtime,
                    vision: vision,
                    generation: generation,
                    inferenceMode: primaryMode,
                    onDelta: { delta in
                        Task { @MainActor in output += delta }
                    }
                )
                await finishSuccess(metrics)
            } catch {
                if primaryMode == .accelerated {
                    await MainActor.run {
                        usedFallback = true
                        output = ""
                        status = "加速模式未完成，正在自动回退…"
                    }

                    do {
                        let metrics = try await engine.runStagedVision(
                            modelURL: modelURL,
                            mmprojURL: mmprojURL,
                            imageURL: imageURL,
                            question: question,
                            runtime: runtime,
                            vision: vision,
                            generation: generation,
                            inferenceMode: .safe,
                            onDelta: { delta in
                                Task { @MainActor in output += delta }
                            }
                        )
                        await finishSuccess(metrics)
                    } catch {
                        await finishFailure(error)
                    }
                } else {
                    await finishFailure(error)
                }
            }
        }
    }

    @MainActor
    private func finishSuccess(
        _ metrics: StagedVisionMetrics
    ) {
        busy = false
        output = metrics.text
        latestMetrics = metrics
        status = (
            metrics.resourceReleasedResidentBeforeEncode ||
            metrics.resourceAdjustedVision
        ) ? "完成（资源保护已介入）" : "完成"
        detail = metrics.summary
    }

    @MainActor
    private func finishFailure(_ error: Error) {
        busy = false
        status = friendlyErrorTitle(error)
        detail = friendlyErrorDetail(error)
    }

    private func friendlyErrorTitle(_ error: Error) -> String {
        let stage = persistedStage()
        if stage.contains("IMAGE") {
            return "图片处理失败"
        }
        if stage.contains("CONTEXT") {
            return "内存或上下文不足"
        }
        if stage.contains("FULL_MODEL") {
            return "主模型加载失败"
        }
        if stage.contains("MMPROJ") {
            return "视觉模型加载失败"
        }
        return "本次运行未完成"
    }

    private func friendlyErrorDetail(_ error: Error) -> String {
        let stage = persistedStage()
        return """
        \(error.localizedDescription)

        诊断阶段：\(stage)
        建议：确认模型文件仍可访问；若使用“加速”模式，App 会自动尝试“安全”模式。仍失败时可进入 Developer Diagnostics 查看完整阶段信息。
        """
    }

    private func persistedStage() -> String {
        let url = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(
            "bonsai_staged_vision_stage.txt"
        )

        return (
            try? String(contentsOf: url, encoding: .utf8)
        )?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            ?? "无"
    }

    private func recoverPreviousFailureHint() {
        let stage = persistedStage()
        guard
            stage != "无",
            stage != "STAGED_99_PASS",
            !stage.hasSuffix("_PASS")
        else {
            return
        }

        status = "检测到上次运行未完成"
        let apiEvidence = persistedAPIPreflight()
        let engineEvidence = persistedEngineStage()
        detail = """
        上次 Staged 阶段：\(stage)。
        Engine 阶段：\(engineEvidence)
        \(apiEvidence.isEmpty ? "" : "API preflight:\n" + apiEvidence)
        """
    }

    private func persistedEngineStage() -> String {
        let url = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(
            "bonsai_engine_stage.txt"
        )
        return (
            try? String(contentsOf: url, encoding: .utf8)
        )?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? "无"
    }

    private func persistedAPIPreflight() -> String {
        let url = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(
            "bonsai_api_preflight.txt"
        )
        return (
            try? String(contentsOf: url, encoding: .utf8)
        )?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
    }

    private func persistedDiagnosticFile(
        _ name: String
    ) -> String {
        let url = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(name)

        return (
            try? String(
                contentsOf: url,
                encoding: .utf8
            )
        )?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? "无"
    }

    private func buildDiagnosticSnapshot() -> String {
        let defaults = UserDefaults.standard
        let capturedAt =
            ISO8601DateFormatter()
                .string(from: Date())

        let version =
            Bundle.main.object(
                forInfoDictionaryKey:
                    "CFBundleShortVersionString"
            ) as? String ?? "?"
        let build =
            Bundle.main.object(
                forInfoDictionaryKey:
                    "CFBundleVersion"
            ) as? String ?? "?"

        let physicalMemoryMiB =
            ProcessInfo.processInfo.physicalMemory
            / 1_048_576

        let mlxMetrics =
            defaults.string(
                forKey:
                    "BonsaiMLXVisionLastMetrics"
            ) ?? "无"
        let apiVisionMetrics =
            defaults.string(
                forKey:
                    "BonsaiRC1231LastAPIVisionMetrics"
            ) ?? "无"
        let apiPerformanceMetrics =
            defaults.string(
                forKey:
                    RC1232PerformanceDiagnostics
                        .defaultsKey
            ) ?? "无"
        let longRunRequestHistory =
            defaults.string(
                forKey:
                    RC1232PerformanceDiagnostics
                        .longRunHistoryDefaultsKey
            ) ?? "无"

        let lastStage =
            defaults.string(
                forKey: "BonsaiLabLastStage"
            ) ?? "无"
        let engineStage =
            persistedEngineStage()
        let twoPhaseStage =
            persistedDiagnosticFile(
                "bonsai_two_phase_vision_stage.txt"
            )
        let mlxVisionStage =
            persistedDiagnosticFile(
                "bonsai_mlx_vision_stage.txt"
            )
        let injectionStage =
            persistedDiagnosticFile(
                "bonsai_mlx_injection_stage.txt"
            )
        let stagedStage =
            persistedStage()

        let visionHeadroom =
            "\(defaults.integer(forKey: "BonsaiLabVisionHeadroomBeforeReleaseMiB"))"
            + " → "
            + "\(defaults.integer(forKey: "BonsaiLabVisionHeadroomAfterReleaseMiB"))"
            + " → "
            + "\(defaults.integer(forKey: "BonsaiLabVisionHeadroomAfterMMProjMiB"))"
            + " → "
            + "\(defaults.integer(forKey: "BonsaiLabVisionHeadroomAfterContextMiB"))"
            + " MiB"

        let bootstrap =
            "ctx="
            + "\(defaults.integer(forKey: "BonsaiLabBootstrapRequestedContext"))"
            + "/b"
            + "\(defaults.integer(forKey: "BonsaiLabBootstrapRequestedBatch"))"
            + "/u"
            + "\(defaults.integer(forKey: "BonsaiLabBootstrapRequestedUBatch"))"
            + ", headroom="
            + "\(defaults.integer(forKey: "BonsaiLabBootstrapHeadroomStartMiB"))"
            + "→"
            + "\(defaults.integer(forKey: "BonsaiLabBootstrapHeadroomAfterVocabMiB"))"
            + "→"
            + "\(defaults.integer(forKey: "BonsaiLabBootstrapHeadroomAfterMMProjMiB"))"
            + "→"
            + "\(defaults.integer(forKey: "BonsaiLabBootstrapHeadroomAfterFullModelMiB"))"
            + "→"
            + "\(defaults.integer(forKey: "BonsaiLabBootstrapHeadroomAfterContextMiB"))"
            + " MiB, Metal="
            + "\(defaults.integer(forKey: "BonsaiLabBootstrapMetalBeforeContextMiB"))"
            + "→"
            + "\(defaults.integer(forKey: "BonsaiLabBootstrapMetalAfterContextMiB"))"
            + "/"
            + "\(defaults.integer(forKey: "BonsaiLabBootstrapMetalRecommendedMiB"))"
            + " MiB"

        let apiPreflight =
            persistedAPIPreflight()
                .isEmpty
                ? "无"
                : persistedAPIPreflight()

        var lines: [String] = [
            "=== BONSAILAB DIAGNOSTIC SNAPSHOT v1 ===",
            "captured_at=\(capturedAt)",
            "app_version=\(version)",
            "build=\(build)",
            "device=\(UIDevice.current.model)",
            "os=\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "physical_memory_mib=\(physicalMemoryMiB)",
            "",
            "[APP]",
            "status=\(status)",
            "busy=\(busy)",
            "detail=\(detail.isEmpty ? "无" : detail)",
            "",
            "[API]",
            "running=\(apiServer.isRunning)",
            "status=\(apiServer.status)",
            "base_url=\(apiServer.baseURL)",
            "model=\(apiServer.modelID)",
            "request_count=\(apiServer.requestCount)",
            "last_error=\(apiServer.lastError.isEmpty ? "无" : apiServer.lastError)",
            "api_key=[REDACTED]",
            "",
            "[SELECTED ASSETS]",
            "main_model=\(modelName)",
            "vision_tower=\(mlxVisionWeightsName)",
            "mmproj=\(mmprojName)",
            "image=\(imageName)",
            "",
            "[RUNTIME]",
            "ui_quality=\(quality.rawValue)",
            "ui_vision_context=\(vision.contextTokens)",
            "ui_image_tokens=\(vision.imageMaxTokens)",
            "ui_batch=\(vision.contextBatch)",
            "ui_ubatch=\(vision.contextUBatch)",
            "api_context=512",
            "api_batch=8",
            "api_ubatch=8",
            "api_flash_attention=false",
            "api_offload_kqv=false",
            "api_op_offload=false",
            "api_kv_unified=true",
            "api_load_mode=mmap",
            "vision_prefix_kv_reuse_enabled="
                + String(
                    defaults.bool(
                        forKey:
                            "BonsaiRC1232VisionPrefixKVReuseEnabled"
                    )
                ),
            "",
            "[STAGES]",
            "last_stage=\(lastStage)",
            "engine_stage=\(engineStage)",
            "two_phase_vision=\(twoPhaseStage)",
            "mlx_vision_stage=\(mlxVisionStage)",
            "live_vision_injection=\(injectionStage)",
            "staged_vision=\(stagedStage)",
            "",
            "[MLX VISION METRICS]",
            mlxMetrics,
            "",
            "[LAST API VISION METRICS]",
            apiVisionMetrics,
            "",
            "[LAST API REQUEST PERFORMANCE]",
            apiPerformanceMetrics,
            "",
            "[RC1.23.3 LONG-RUN REQUEST HISTORY]",
            longRunRequestHistory,
            "",
            "[RESOURCE / MEMORY]",
            "vision_headroom=\(visionHeadroom)",
            "projector_first_bootstrap=\(bootstrap)",
            "",
            "[API PREFLIGHT]",
            apiPreflight,
            "",
            "[PRIVACY]",
            "api_key=REDACTED",
            "raw_image=NOT_INCLUDED",
            "base64=NOT_INCLUDED",
            "prompt_text=NOT_INCLUDED",
            "assistant_output=NOT_INCLUDED",
            "=== END BONSAILAB DIAGNOSTIC SNAPSHOT ===",
        ]

        lines.removeAll {
            $0.contains("Optional(")
        }
        return lines.joined(separator: "\n")
    }

    private func startAPIServer() {
        guard let selectedModelURL = modelURL else {
            status = "请先选择主模型"
            return
        }

        let selectedMLXVisionWeightsURL =
            mlxVisionWeightsURL
        let selectedRuntime = runtime
        let sharedEngine = engine
        let sharedVisionSidecar = mlxVisionSidecar

        busy = true
        status = "正在预热 RC1.23.1 Runtime…"
        detail = """
        Text API 继续使用冻结的 RC1.20.7 路径。
        单图请求使用 RC1.23.0 MLX Live Vision Injection；
        不初始化 mmproj，不要求 App 重启。
        """

        Task {
            do {
                await sharedEngine.unloadAll()

                var apiRuntime = selectedRuntime
                apiRuntime.context = 512
                apiRuntime.batch = 8
                apiRuntime.ubatch = 8
                apiRuntime.flashAttention = false
                apiRuntime.offloadKQV = false
                apiRuntime.opOffload = false
                apiRuntime.kvUnified = true
                apiRuntime.loadMode = .mmap

                _ = try await sharedEngine.loadModel(
                    url: selectedModelURL,
                    runtime: apiRuntime
                )

                RC1232PerformanceDiagnostics.beginSession()

                try apiServer.start(port: 8080) {
                    payload,
                    onDelta in

                    let requestID =
                        UUID().uuidString
                    let requestOrdinal =
                        RC1232PerformanceDiagnostics
                            .nextRequestOrdinal()
                    let requestStart =
                        RC1232PerformanceDiagnostics.now()
                    let requestRoute =
                        payload.imageData == nil
                        ? "text"
                        : "vision"
                    var requestMetricsCommitted = false

                    defer {
                        if !requestMetricsCommitted {
                            let lastStage =
                                UserDefaults.standard.string(
                                    forKey:
                                        "BonsaiLabLastStage"
                                ) ?? "无"
                            RC1232PerformanceDiagnostics
                                .persistFailure(
                                    requestID: requestID,
                                    requestOrdinal:
                                        requestOrdinal,
                                    route: requestRoute,
                                    stream: payload.stream,
                                    requestStart: requestStart,
                                    lastStage: lastStage
                                )
                        }
                    }

                    var gen = GenerationConfig()
                    gen.maxTokens = min(
                        payload.maxTokens,
                        256
                    )

                    let reasoningInstruction: String
                    switch payload.reasoningEffort {
                    case "xhigh":
                        reasoningInstruction =
                            "Reasoning effort is set to xhigh. "
                            + "Please think carefully through the task, "
                            + "validate key assumptions, consider plausible "
                            + "alternatives, and prioritize correctness, "
                            + "consistency, and clarity in the final answer."
                    case "low":
                        reasoningInstruction =
                            "Reasoning effort is set to low. "
                            + "Keep your thinking brief and focused, moving "
                            + "directly to the conclusion without unnecessary "
                            + "elaboration."
                    default:
                        reasoningInstruction = ""
                    }

                    let apiSystemPrompt: String
                    if reasoningInstruction.isEmpty {
                        apiSystemPrompt =
                            payload.systemPrompt
                    } else {
                        apiSystemPrompt =
                            payload.systemPrompt
                            + "\n\n"
                            + reasoningInstruction
                    }

                    if let imageData = payload.imageData {
                        guard
                            let selectedMLXVisionWeightsURL
                        else {
                            throw OpenAIHandlerHTTPError(
                                status: 422,
                                code:
                                    "vision_model_unavailable",
                                message:
                                    "图片请求需要先选择 "
                                    + "vision_tower.safetensors。"
                            )
                        }

                        let imageURL = FileManager.default
                            .temporaryDirectory
                            .appendingPathComponent(
                                "bonsai-api-"
                                + UUID().uuidString
                            )
                            .appendingPathExtension(
                                payload.imageExtension
                            )

                        let imageWriteStart =
                            RC1232PerformanceDiagnostics.now()
                        do {
                            try imageData.write(
                                to: imageURL,
                                options: .atomic
                            )
                        } catch {
                            throw OpenAIHandlerHTTPError(
                                status: 400,
                                code: "image_decode_failed",
                                message:
                                    "无法准备 API 图片临时文件。"
                            )
                        }

                        defer {
                            try? FileManager.default
                                .removeItem(at: imageURL)
                        }

                        // RC1.23.0's frozen BVCACHE1 prefill is
                        // vision-first inside the user turn. The
                        // normalizer preserves the client ordering for
                        // diagnostics, while this adapter explicitly
                        // targets that proven fixed runtime layout.
                        UserDefaults.standard.set(
                            payload.imageOrdering.rawValue,
                            forKey:
                                "BonsaiRC1231LastImageOrdering"
                        )

                        let imageWriteEnd =
                            RC1232PerformanceDiagnostics.now()
                        let visionEncodeStart =
                            imageWriteEnd

                        let packet: MLXVisionEmbeddingPacket
                        do {
                            packet =
                                try await sharedVisionSidecar
                                    .encodeForInjection(
                                        weightsURL:
                                            selectedMLXVisionWeightsURL,
                                        imageURL:
                                            imageURL
                                    )
                        } catch let error
                            as MLXVisionSidecarError {
                            await sharedVisionSidecar
                                .cleanupAfterRequestFailure()
                            await sharedEngine
                                .cleanupAfterRequestFailure()

                            switch error {
                            case .invalidImage,
                                 .invalidDimensions:
                                throw OpenAIHandlerHTTPError(
                                    status: 400,
                                    code:
                                        "image_decode_failed",
                                    message:
                                        error.localizedDescription
                                )
                            case .noVisionWeights:
                                throw OpenAIHandlerHTTPError(
                                    status: 422,
                                    code:
                                        "vision_model_unavailable",
                                    message:
                                        error.localizedDescription
                                )
                            case .unexpectedOutput:
                                throw OpenAIHandlerHTTPError(
                                    status: 422,
                                    code:
                                        "vision_embedding_invalid",
                                    message:
                                        error.localizedDescription
                                )
                            case .missingBlockWeights:
                                throw OpenAIHandlerHTTPError(
                                    status: 500,
                                    code:
                                        "vision_inference_failed",
                                    message:
                                        error.localizedDescription
                                )
                            }
                        } catch {
                            await sharedVisionSidecar
                                .cleanupAfterRequestFailure()
                            await sharedEngine
                                .cleanupAfterRequestFailure()
                            throw OpenAIHandlerHTTPError(
                                status: 500,
                                code:
                                    "vision_inference_failed",
                                message:
                                    error.localizedDescription
                            )
                        }

                        guard
                            packet.metrics.outputTokens > 0,
                            packet.metrics.outputDimension
                                == 5_120,
                            packet.gridX > 0,
                            packet.gridY > 0,
                            packet.gridX * packet.gridY
                                == packet.metrics.outputTokens,
                            packet.float32Embeddings.count
                                == packet.metrics.outputTokens
                                * packet.metrics.outputDimension
                                * MemoryLayout<Float>.size
                        else {
                            await sharedVisionSidecar
                                .cleanupAfterRequestFailure()
                            await sharedEngine
                                .cleanupAfterRequestFailure()
                            throw OpenAIHandlerHTTPError(
                                status: 422,
                                code:
                                    "vision_embedding_invalid",
                                message:
                                    "MLX Vision 输出无法安全注入 27B。"
                            )
                        }

                        let visionEncodeEnd =
                            RC1232PerformanceDiagnostics.now()

                        let imageMaxTokens =
                            VisionConfig.low512
                                .imageMaxTokens

                        let cacheWriteStart =
                            visionEncodeEnd
                        let cacheURL: URL
                        do {
                            cacheURL =
                                try await sharedEngine
                                    .writeMLXProjectedVisionCache(
                                        modelURL:
                                            selectedModelURL,
                                        weightsURL:
                                            selectedMLXVisionWeightsURL,
                                        imageURL:
                                            imageURL,
                                        embeddingData:
                                            packet.float32Embeddings,
                                        nTokens:
                                            packet.metrics.outputTokens,
                                        projectionDimension:
                                            packet.metrics.outputDimension,
                                        gridX:
                                            packet.gridX,
                                        gridY:
                                            packet.gridY,
                                        imageMaxTokens:
                                            imageMaxTokens
                                    )
                        } catch {
                            await sharedVisionSidecar
                                .cleanupAfterRequestFailure()
                            await sharedEngine
                                .cleanupAfterRequestFailure()
                            throw OpenAIHandlerHTTPError(
                                status: 500,
                                code:
                                    "vision_injection_failed",
                                message:
                                    error.localizedDescription
                            )
                        }

                        let cacheWriteEnd =
                            RC1232PerformanceDiagnostics.now()
                        let generationStart =
                            cacheWriteEnd

                        let metrics: VisionMetrics
                        do {
                            metrics =
                                try await sharedEngine
                                    .generateCachedVision(
                                        cacheURL: cacheURL,
                                        imageMaxTokens:
                                            imageMaxTokens,
                                        systemPrompt:
                                            apiSystemPrompt,
                                        question:
                                            payload.userPrompt,
                                        generation: gen,
                                        reasoningEffort:
                                            payload.reasoningEffort,
                                        requireFullOutputBudget:
                                            true,
                                        enablePrefixReuse:
                                            UserDefaults.standard
                                                .bool(
                                                    forKey:
                                                        "BonsaiRC1232VisionPrefixKVReuseEnabled"
                                                ),
                                        onDelta: onDelta
                                    )
                        } catch let error as LabError {
                            await sharedVisionSidecar
                                .cleanupAfterRequestFailure()
                            await sharedEngine
                                .cleanupAfterRequestFailure()

                            if case .promptTooLong = error {
                                throw OpenAIHandlerHTTPError(
                                    status: 400,
                                    code:
                                        "context_length_exceeded",
                                    message:
                                        error.localizedDescription
                                )
                            }

                            throw OpenAIHandlerHTTPError(
                                status: 500,
                                code:
                                    "vision_injection_failed",
                                message:
                                    error.localizedDescription
                            )
                        } catch {
                            await sharedVisionSidecar
                                .cleanupAfterRequestFailure()
                            await sharedEngine
                                .cleanupAfterRequestFailure()
                            throw OpenAIHandlerHTTPError(
                                status: 500,
                                code:
                                    "vision_injection_failed",
                                message:
                                    error.localizedDescription
                            )
                        }

                        let requestEnd =
                            RC1232PerformanceDiagnostics.now()
                        let prefixReuseEnabled =
                            UserDefaults.standard.bool(
                                forKey:
                                    "BonsaiRC1232VisionPrefixKVReuseEnabled"
                            )

                        let resourceSnapshot =
                            await sharedEngine
                                .apiAdmissionSnapshot()

                        RC1232PerformanceDiagnostics
                            .persistVisionSuccess(
                                requestID: requestID,
                                requestOrdinal:
                                    requestOrdinal,
                                stream: payload.stream,
                                packet: packet,
                                metrics: metrics,
                                imageOrdering:
                                    payload.imageOrdering,
                                prefixReuseEnabled:
                                    prefixReuseEnabled,
                                resourceSnapshot:
                                    resourceSnapshot,
                                imageWriteStart:
                                    imageWriteStart,
                                imageWriteEnd:
                                    imageWriteEnd,
                                visionEncodeStart:
                                    visionEncodeStart,
                                visionEncodeEnd:
                                    visionEncodeEnd,
                                cacheWriteStart:
                                    cacheWriteStart,
                                cacheWriteEnd:
                                    cacheWriteEnd,
                                requestStart:
                                    requestStart,
                                requestEnd:
                                    requestEnd
                            )
                        requestMetricsCommitted = true

                        UserDefaults.standard.set(
                            RC1232PerformanceDiagnostics
                                .visionSummary(
                                    packet: packet,
                                    imageOrdering:
                                        payload.imageOrdering,
                                    metrics: metrics
                                ),
                            forKey:
                                "BonsaiRC1231LastAPIVisionMetrics"
                        )

                        return OpenAIHandlerResult(
                            text:
                                metrics.generation.text,
                            promptTokens:
                                metrics.generation
                                    .promptTokens,
                            completionTokens:
                                metrics.generation
                                    .generatedTokens,
                            finishReason:
                                metrics.generation
                                    .generatedTokens
                                    >= gen.maxTokens
                                    ? "length"
                                    : "stop"
                        )
                    }

                    let textGenerationStart =
                        RC1232PerformanceDiagnostics.now()
                    let metrics =
                        try await sharedEngine.generateText(
                            systemPrompt:
                                apiSystemPrompt,
                            userPrompt:
                                payload.userPrompt,
                            generation: gen,
                            reasoningEffort:
                                payload.reasoningEffort,
                            onDelta: onDelta
                        )

                    let textGenerationEnd =
                        RC1232PerformanceDiagnostics.now()

                    let resourceSnapshot =
                        await sharedEngine
                            .apiAdmissionSnapshot()

                    RC1232PerformanceDiagnostics
                        .persistTextSuccess(
                            requestID: requestID,
                            requestOrdinal:
                                requestOrdinal,
                            stream: payload.stream,
                            metrics: metrics,
                            resourceSnapshot:
                                resourceSnapshot,
                            textGenerationStart:
                                textGenerationStart,
                            textGenerationEnd:
                                textGenerationEnd,
                            requestStart:
                                requestStart
                        )
                    requestMetricsCommitted = true

                    return OpenAIHandlerResult(
                        text: metrics.text,
                        promptTokens:
                            metrics.promptTokens,
                        completionTokens:
                            metrics.generatedTokens,
                        finishReason:
                            metrics.generatedTokens
                                >= gen.maxTokens
                                ? "length"
                                : "stop"
                    )
                }

                await MainActor.run {
                    busy = false
                    status =
                        "RC1.23.1 API Runtime 已预热"
                    detail =
                        selectedMLXVisionWeightsURL == nil
                        ? "文本 API 可用；选择 vision_tower.safetensors 后启用单图 MLX 多模态 API。"
                        : "文本 + MLX Live Vision OpenAI API 已就绪。"
                }
            } catch {
                apiServer.stop()
                await sharedEngine.unloadAll()

                await MainActor.run {
                    busy = false
                    status =
                        "RC1.23.1 Runtime 预热失败"
                    detail = error.localizedDescription
                }
            }
        }
    }

    private func copyAPIConfig() {
        let text = """
        Base URL: \(apiServer.baseURL)
        Model: \(apiServer.modelID)
        API Key: \(apiServer.apiKey)
        """

        UIPasteboard.general.string = text
        status = "API 配置已复制"
    }

    private func runCertification() {
        guard
            let modelURL,
            let mmprojURL,
            let imageURL
        else {
            return
        }

        busy = true
        certification = []
        warmSessionSummary = ""
        warmSessionPass = nil
        status = "正在进行设备认证…"
        detail = ""

        Task {
            var rows: [CertificationResult] = []

            for level in VisionQuality.allCases {
                var gen = GenerationConfig()
                gen.maxTokens = 64

                do {
                    let metrics = try await engine.runStagedVision(
                        modelURL: modelURL,
                        mmprojURL: mmprojURL,
                        imageURL: imageURL,
                        question: "请简要描述图片中的主要内容。",
                        runtime: runtime,
                        vision: level.preset.config,
                        generation: gen,
                        inferenceMode: .accelerated,
                        resourceGovernorEnabled: false
                    )

                    let reuseSummary =
                        " · cache " + (metrics.imageCacheHit ? "HIT" : "MISS")
                        + " · model " + (metrics.residentModelHit ? "HIT" : "MISS")

                    rows.append(
                        CertificationResult(
                            quality: level,
                            pass: true,
                            summary: String(
                                format:
                                    "%.2f tok/s · img %.2fs · load %.2fs",
                                metrics.tokensPerSecond,
                                metrics.imageEncodeSeconds,
                                metrics.fullModelLoadSeconds
                            ) + reuseSummary
                        )
                    )
                } catch {
                    rows.append(
                        CertificationResult(
                            quality: level,
                            pass: false,
                            summary: error.localizedDescription
                        )
                    )
                }

                await MainActor.run {
                    certification = rows
                }
            }

            var warmPass = false
            var warmSummary = ""

            do {
                var warmGen = GenerationConfig()
                warmGen.maxTokens = 48

                _ = try await engine.runStagedVision(
                    modelURL: modelURL,
                    mmprojURL: mmprojURL,
                    imageURL: imageURL,
                    question: "请用一句话概括这张图片。",
                    runtime: runtime,
                    vision: VisionPreset.mid768.config,
                    generation: warmGen,
                    inferenceMode: .accelerated,
                    resourceGovernorEnabled: false
                )

                let warm = try await engine.runStagedVision(
                    modelURL: modelURL,
                    mmprojURL: mmprojURL,
                    imageURL: imageURL,
                    question: "再补充一个上一轮没有提到的细节。",
                    runtime: runtime,
                    vision: VisionPreset.mid768.config,
                    generation: warmGen,
                    inferenceMode: .accelerated,
                    resourceGovernorEnabled: false
                )

                warmPass =
                    warm.imageCacheHit &&
                    warm.residentModelHit &&
                    warm.residentContextHit &&
                    warm.kvReuseHit &&
                    warm.fullModelLoadSeconds < 0.05 &&
                    warm.contextCreateSeconds < 0.05

                warmSummary =
                    "cache " + (warm.imageCacheHit ? "HIT" : "MISS")
                    + " · model " + (warm.residentModelHit ? "HIT" : "MISS")
                    + " · context " + (warm.residentContextHit ? "HIT" : "MISS")
                    + " · KV " + (warm.kvReuseHit ? "HIT" : "MISS")
                    + String(
                        format:
                            " · load %.3fs · ctx %.3fs",
                        warm.fullModelLoadSeconds,
                        warm.contextCreateSeconds
                    )
            } catch {
                warmSummary = "warm-session test error: \(error.localizedDescription)"
            }

            await MainActor.run {
                warmSessionPass = warmPass
                warmSessionSummary = warmSummary
                busy = false
                status = rows.allSatisfy(\.pass) && warmPass
                    ? "设备认证通过"
                    : "设备认证完成（存在未通过项）"
            }
        }
    }
}

private enum ProductAPIError: LocalizedError {
    case mmprojRequired

    var errorDescription: String? {
        switch self {
        case .mmprojRequired:
            return "该请求包含图片，但当前没有选择 mmproj 视觉模型。"
        }
    }
}

private struct CertificationResult: Identifiable {
    let id = UUID()
    let quality: VisionQuality
    let pass: Bool
    let summary: String
}
