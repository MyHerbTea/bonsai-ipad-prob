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
    struct RequestObservation {
        let ordinal: Int
        let start: UInt64
        let idleGapMilliseconds: Double
        let sessionElapsedMilliseconds: Double
        let thermalStart: String
        let lowPowerModeStart: Bool
    }

    private struct RequestCompletionObservation {
        let end: UInt64
        let sessionElapsedMilliseconds: Double
        let thermalEnd: String
        let lowPowerModeEnd: Bool
    }

    private static var sessionRequestOrdinal = 0
    private static var sessionStartNanoseconds: UInt64 = 0
    private static var previousRequestEndNanoseconds: UInt64?
    private static let historyLimit = 32

    static func beginSession() {
        stateQueue.sync {
            sessionRequestOrdinal = 0
            sessionStartNanoseconds = now()
            previousRequestEndNanoseconds = nil
            UserDefaults.standard.removeObject(
                forKey: longRunHistoryDefaultsKey
            )
        }
    }

    static func beginRequest() -> RequestObservation {
        stateQueue.sync {
            let start = now()
            sessionRequestOrdinal += 1

            let idleGapMilliseconds: Double
            if let previousRequestEndNanoseconds {
                idleGapMilliseconds =
                    milliseconds(
                        from: previousRequestEndNanoseconds,
                        to: start
                    )
            } else {
                idleGapMilliseconds = -1
            }

            return RequestObservation(
                ordinal: sessionRequestOrdinal,
                start: start,
                idleGapMilliseconds:
                    idleGapMilliseconds,
                sessionElapsedMilliseconds:
                    milliseconds(
                        from: sessionStartNanoseconds,
                        to: start
                    ),
                thermalStart:
                    thermalStateName(
                        ProcessInfo.processInfo.thermalState
                    ),
                lowPowerModeStart:
                    ProcessInfo.processInfo
                        .isLowPowerModeEnabled
            )
        }
    }

    private static func thermalStateName(
        _ state: ProcessInfo.ThermalState
    ) -> String {
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }

    private static func completeRequest(
        _ observation: RequestObservation
    ) -> RequestCompletionObservation {
        let end = now()
        let completion =
            RequestCompletionObservation(
                end: end,
                sessionElapsedMilliseconds:
                    milliseconds(
                        from: sessionStartNanoseconds,
                        to: end
                    ),
                thermalEnd:
                    thermalStateName(
                        ProcessInfo.processInfo.thermalState
                    ),
                lowPowerModeEnd:
                    ProcessInfo.processInfo
                        .isLowPowerModeEnabled
            )

        stateQueue.sync {
            if let previousRequestEndNanoseconds {
                self.previousRequestEndNanoseconds =
                    max(
                        previousRequestEndNanoseconds,
                        end
                    )
            } else {
                previousRequestEndNanoseconds = end
            }
        }

        return completion
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
        observation: RequestObservation,
        route: String,
        stream: Bool,
        lastStage: String
    ) {
        let completion = completeRequest(observation)
        let totalMilliseconds =
            formatMilliseconds(
                milliseconds(
                    from: observation.start,
                    to: completion.end
                )
            )
        let environment = [
            "idle_gap_ms="
                + formatMilliseconds(
                    observation.idleGapMilliseconds
                ),
            "session_elapsed_start_ms="
                + formatMilliseconds(
                    observation.sessionElapsedMilliseconds
                ),
            "session_elapsed_end_ms="
                + formatMilliseconds(
                    completion.sessionElapsedMilliseconds
                ),
            "thermal_state_start="
                + observation.thermalStart,
            "thermal_state_end="
                + completion.thermalEnd,
            "low_power_mode_start="
                + String(observation.lowPowerModeStart),
            "low_power_mode_end="
                + String(completion.lowPowerModeEnd),
        ]
        persist([
            "request_id=\(requestID)",
            "request_ordinal=\(observation.ordinal)",
            "route=\(route)",
            "stream=\(stream)",
            "result=failed_or_interrupted",
            "total_ms=" + totalMilliseconds,
            "last_stage=\(lastStage)",
        ] + environment)
        appendLongRunHistory([
            "ordinal=\(observation.ordinal)",
            "route=\(route)",
            "result=failed_or_interrupted",
            "total_ms=\(totalMilliseconds)",
            "idle_gap_ms="
                + formatMilliseconds(
                    observation.idleGapMilliseconds
                ),
            "session_elapsed_ms="
                + formatMilliseconds(
                    completion.sessionElapsedMilliseconds
                ),
            "thermal_start=\(observation.thermalStart)",
            "thermal_end=\(completion.thermalEnd)",
            "low_power_start=\(observation.lowPowerModeStart)",
            "low_power_end=\(completion.lowPowerModeEnd)",
            "last_stage=\(lastStage)",
        ])
    }

    static func persistVisionSuccess(
        requestID: String,
        observation: RequestObservation,
        stream: Bool,
        packet: MLXVisionEmbeddingPacket,
        metrics: VisionMetrics,
        requestedMaxTokens: Int,
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
        let suffixBatchUtilization =
            String(
                format: "%.4f",
                metrics.suffixBatchUtilization
            )
        let suffixMillisecondsPerDecodeCall =
            metrics.suffixDecodeCalls > 0
                ? formatMilliseconds(
                    metrics.suffixPrefillSeconds
                        * 1_000
                        / Double(metrics.suffixDecodeCalls)
                )
                : "0.000"
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
        let completion = completeRequest(observation)
        let environment = [
            "idle_gap_ms="
                + formatMilliseconds(
                    observation.idleGapMilliseconds
                ),
            "session_elapsed_start_ms="
                + formatMilliseconds(
                    observation.sessionElapsedMilliseconds
                ),
            "session_elapsed_end_ms="
                + formatMilliseconds(
                    completion.sessionElapsedMilliseconds
                ),
            "thermal_state_start="
                + observation.thermalStart,
            "thermal_state_end="
                + completion.thermalEnd,
            "low_power_mode_start="
                + String(observation.lowPowerModeStart),
            "low_power_mode_end="
                + String(completion.lowPowerModeEnd),
        ]

        persist([
            "request_id=\(requestID)",
            "request_ordinal=\(observation.ordinal)",
            "route=vision",
            "stream=\(stream)",
            "result=success",
            "requested_max_tokens=\(requestedMaxTokens)",
            "effective_max_tokens=\(metrics.generation.effectiveMaxTokens)",
            "termination_reason=\(metrics.generation.terminationReason.rawValue)",
            "finish_reason=\(metrics.generation.terminationReason.openAIFinishReason)",
            "ttft_ms="
                + formatMilliseconds(
                    metrics.generation.ttftSeconds * 1_000
                ),
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
            "rc1235_suffix_tokens=\(metrics.suffixTokenCount)",
            "rc1235_suffix_decode_calls=\(metrics.suffixDecodeCalls)",
            "rc1235_suffix_batch_capacity=\(metrics.suffixBatchCapacity)",
            "rc1235_suffix_ubatch_capacity=\(metrics.suffixUBatchCapacity)",
            "rc1235_suffix_last_batch_tokens=\(metrics.suffixLastBatchTokens)",
            "rc1235_suffix_batch_utilization=" + suffixBatchUtilization,
            "rc1235_suffix_ms_per_decode_call="
                + suffixMillisecondsPerDecodeCall,
            "cache_reuse="
                + (metrics.prefixReuseHit
                    ? "vision_prefix_kv_hit"
                    : "vision_prefix_kv_miss"),
            "total_ms=" + totalMilliseconds,
        ] + environment + resources)

        appendLongRunHistory([
            "ordinal=\(observation.ordinal)",
            "route=vision",
            "result=success",
            "requested_max_tokens=\(requestedMaxTokens)",
            "effective_max_tokens=\(metrics.generation.effectiveMaxTokens)",
            "completion_tokens=\(metrics.generation.generatedTokens)",
            "termination_reason=\(metrics.generation.terminationReason.rawValue)",
            "finish_reason=\(metrics.generation.terminationReason.openAIFinishReason)",
            "hit=\(metrics.prefixReuseHit)",
            "retained=\(metrics.prefixRetainedForReuse)",
            "total_ms=\(totalMilliseconds)",
            "prefill_ms=\(prefillMilliseconds)",
            "suffix_prefill_ms=\(suffixPrefillMilliseconds)",
            "rc1235_suffix_tokens=\(metrics.suffixTokenCount)",
            "rc1235_suffix_decode_calls=\(metrics.suffixDecodeCalls)",
            "rc1235_suffix_batch_capacity=\(metrics.suffixBatchCapacity)",
            "rc1235_suffix_ubatch_capacity=\(metrics.suffixUBatchCapacity)",
            "rc1235_suffix_last_batch_tokens=\(metrics.suffixLastBatchTokens)",
            "rc1235_suffix_batch_utilization=\(suffixBatchUtilization)",
            "rc1235_suffix_ms_per_decode_call=\(suffixMillisecondsPerDecodeCall)",
            "decode_ms=\(decodeMilliseconds)",
            "tokens_per_second=\(tokensPerSecond)",
            "vision_encode_ms=\(visionEncodeMilliseconds)",
            "idle_gap_ms="
                + formatMilliseconds(
                    observation.idleGapMilliseconds
                ),
            "session_elapsed_ms="
                + formatMilliseconds(
                    completion.sessionElapsedMilliseconds
                ),
            "thermal_start=\(observation.thermalStart)",
            "thermal_end=\(completion.thermalEnd)",
            "low_power_start=\(observation.lowPowerModeStart)",
            "low_power_end=\(completion.lowPowerModeEnd)",
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
        observation: RequestObservation,
        stream: Bool,
        metrics: GenerationMetrics,
        requestedMaxTokens: Int,
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
        let completion = completeRequest(observation)
        let environment = [
            "idle_gap_ms="
                + formatMilliseconds(
                    observation.idleGapMilliseconds
                ),
            "session_elapsed_start_ms="
                + formatMilliseconds(
                    observation.sessionElapsedMilliseconds
                ),
            "session_elapsed_end_ms="
                + formatMilliseconds(
                    completion.sessionElapsedMilliseconds
                ),
            "thermal_state_start="
                + observation.thermalStart,
            "thermal_state_end="
                + completion.thermalEnd,
            "low_power_mode_start="
                + String(observation.lowPowerModeStart),
            "low_power_mode_end="
                + String(completion.lowPowerModeEnd),
        ]

        persist([
            "request_id=\(requestID)",
            "request_ordinal=\(observation.ordinal)",
            "route=text",
            "stream=\(stream)",
            "result=success",
            "requested_max_tokens=\(requestedMaxTokens)",
            "effective_max_tokens=\(metrics.effectiveMaxTokens)",
            "termination_reason=\(metrics.terminationReason.rawValue)",
            "finish_reason=\(metrics.terminationReason.openAIFinishReason)",
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
        ] + environment + resources)

        appendLongRunHistory([
            "ordinal=\(observation.ordinal)",
            "route=text",
            "result=success",
            "requested_max_tokens=\(requestedMaxTokens)",
            "effective_max_tokens=\(metrics.effectiveMaxTokens)",
            "completion_tokens=\(metrics.generatedTokens)",
            "termination_reason=\(metrics.terminationReason.rawValue)",
            "finish_reason=\(metrics.terminationReason.openAIFinishReason)",
            "total_ms=\(totalMilliseconds)",
            "decode_ms=\(decodeMilliseconds)",
            "tokens_per_second=\(tokensPerSecond)",
            "idle_gap_ms="
                + formatMilliseconds(
                    observation.idleGapMilliseconds
                ),
            "session_elapsed_ms="
                + formatMilliseconds(
                    completion.sessionElapsedMilliseconds
                ),
            "thermal_start=\(observation.thermalStart)",
            "thermal_end=\(completion.thermalEnd)",
            "low_power_start=\(observation.lowPowerModeStart)",
            "low_power_end=\(completion.lowPowerModeEnd)",
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
    @StateObject private var certificationRecorder =
        CertificationRunRecorder()

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
    @AppStorage("BonsaiRC1233APIRuntimeProfile")
    private var apiRuntimeProfile = "accelerated"
    @AppStorage("BonsaiRC1235APIContextProfile")
    private var apiContextProfile = "512"

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
    @State private var certificationRunnerRunning = false
    @State private var certificationRunnerProgress = "Ready"
    private let certificationCycles = 4
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

                Section("RC1.23.6 Restart Certification") {
                    LabeledContent(
                        "Runner",
                        value: certificationRunnerProgress
                    )

                    LabeledContent(
                        "Recorder",
                        value: certificationRecorder.statusText
                    )

                    LabeledContent(
                        "自动采集",
                        value:
                            "\(certificationRecorder.eventCount) events · "
                            + "\(certificationRecorder.snapshotCount) snapshots"
                    )

                    Button("运行 Restart Certification") {
                        runRestartCertification()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        certificationRunnerRunning
                        || busy
                        || modelURL == nil
                        || mlxVisionWeightsURL == nil
                        || imageURL == nil
                        || certificationRecorder.isRecording
                    )

                    if certificationRunnerRunning {
                        ProgressView()
                    }

                    if let archiveURL =
                        certificationRecorder.latestArchiveURL {
                        ShareLink(item: archiveURL) {
                            Label("分享最近测试结果", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Text("暂无可分享的测试存档")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button("刷新测试存档") {
                        certificationRecorder
                            .refreshLatestArchiveFromDisk()
                    }

                    Text(
                        "只需选择主模型、Vision Tower 和测试图片后点击一次。Build 51 固定使用 Accelerated + 512 context，自动执行 4 轮 stop → awaited unload → start → seed → warm，并把全部生命周期事件与诊断写入一个 BONSAI-RUN-*.json。崩溃后重新打开 App 会自动恢复并扫描最近存档。"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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

                        Picker(
                            "实验：API Runtime Profile",
                            selection: $apiRuntimeProfile
                        ) {
                            Text("Safe").tag("safe")
                            Text("Full").tag("accelerated")
                        }
                        .pickerStyle(.segmented)
                        .disabled(apiServer.isRunning)

                        Text(
                            apiRuntimeProfile == "safe"
                                ? "Safe：兼容回退档，Flash/KQV/Op Offload 均关闭。"
                                : "Full：RC1.23.3 推荐性能档，开启 Flash Attention + KQV/Op Offload。"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                        LabeledContent(
                            "API Context",
                            value: "512 · RC1.23.4 Frozen"
                        )

                        Text(
                            "RC1.23.5 的 256 Dynamic Context 实验已被真机 A/B 拒绝。RC1.23.6 固定回到 512，不再暴露 256 选择入口。"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)

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
                if apiRuntimeProfile == "flash" {
                    apiRuntimeProfile = "accelerated"
                }
                if apiContextProfile != "512" {
                    apiContextProfile = "512"
                }
                certificationRecorder
                    .recoverInterruptedRunIfNeeded()
                certificationRecorder
                    .refreshLatestArchiveFromDisk()
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

        let requestedAPIRuntimeProfile =
            defaults.string(
                forKey: "BonsaiRC1233APIRuntimeProfile"
            ) ?? "safe"
        let activeAPIRuntimeProfile =
            defaults.string(
                forKey: "BonsaiRC1233ActiveAPIRuntimeProfile"
            ) ?? "none"
        let effectiveAPIRuntimeProfile =
            apiServer.isRunning
                ? activeAPIRuntimeProfile
                : requestedAPIRuntimeProfile
        let apiFlashAttention =
            effectiveAPIRuntimeProfile == "flash"
            || effectiveAPIRuntimeProfile == "accelerated"
        let apiOffloadKQV =
            effectiveAPIRuntimeProfile == "accelerated"
        let apiOpOffload =
            effectiveAPIRuntimeProfile == "accelerated"

        let requestedAPIContextProfile = "512"
        let requestedAPIContext = 512
        let activeAPIContext =
            defaults.integer(
                forKey: "BonsaiRC1235ActiveAPIContext"
            )
        let effectiveAPIContext =
            apiServer.isRunning && activeAPIContext > 0
                ? activeAPIContext
                : requestedAPIContext

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
            "api_context=\(effectiveAPIContext)",
            "rc1235_api_context_requested=\(requestedAPIContext)",
            "rc1235_api_context_active=\(activeAPIContext)",
            "rc1235_api_context_profile=\(requestedAPIContextProfile)",
            "api_batch=8",
            "api_ubatch=8",
            "api_runtime_profile=\(effectiveAPIRuntimeProfile)",
            "api_runtime_profile_requested=\(requestedAPIRuntimeProfile)",
            "api_flash_attention=\(apiFlashAttention)",
            "api_offload_kqv=\(apiOffloadKQV)",
            "api_op_offload=\(apiOpOffload)",
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

    private struct RestartCertificationHTTPResult {
        let statusCode: Int
        let elapsedMilliseconds: Double
        let completionTokens: Int
        let finishReason: String
    }

    private enum RestartCertificationError: LocalizedError {
        case apiReadyTimeout
        case invalidLoopbackURL
        case invalidHTTPResponse
        case unexpectedHTTPStatus(Int)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .apiReadyTimeout:
                return "API did not become ready before timeout."
            case .invalidLoopbackURL:
                return "Unable to construct loopback API URL."
            case .invalidHTTPResponse:
                return "Loopback API returned a non-HTTP response."
            case .unexpectedHTTPStatus(let status):
                return "Loopback API returned HTTP \(status)."
            case .malformedResponse:
                return "Loopback API response could not be parsed."
            }
        }
    }

    private func runRestartCertification() {
        guard
            let modelURL,
            let mlxVisionWeightsURL,
            let imageURL
        else {
            status =
                "Restart Certification 需要主模型、Vision Tower 和测试图片"
            return
        }

        if certificationRunnerRunning {
            return
        }

        apiRuntimeProfile = "accelerated"
        apiContextProfile = "512"
        visionPrefixKVReuseEnabled = true
        certificationRunnerRunning = true
        certificationRunnerProgress = "Preparing"

        let build =
            Bundle.main.object(
                forInfoDictionaryKey:
                    "CFBundleVersion"
            ) as? String ?? "?"

        let environment: [String: String] = [
            "device": UIDevice.current.model,
            "os":
                UIDevice.current.systemName
                + " "
                + UIDevice.current.systemVersion,
            "physical_memory_mib":
                String(
                    ProcessInfo.processInfo.physicalMemory
                    / 1_048_576
                ),
            "main_model": modelName,
            "vision_tower": mlxVisionWeightsName,
            "test_image": imageName,
            "runtime_profile": "accelerated",
            "api_context": "512",
            "api_batch": "8",
            "api_ubatch": "8",
            "vision_prefix_kv_reuse_enabled": "true",
            "cycles": String(certificationCycles),
        ]

        guard
            certificationRecorder.startRun(
                stage:
                    "RC1.23.6 One-Click Restart Certification",
                build: build,
                environment: environment
            ) != nil
        else {
            certificationRunnerRunning = false
            certificationRunnerProgress =
                "Recorder could not start"
            return
        }

        certificationRecorder.recordEvent(
            "runner_started",
            fields: [
                "cycles": String(certificationCycles),
                "context": "512",
                "runtime": "accelerated",
            ]
        )
        certificationRecorder.recordSnapshot(
            label: "runner_initial_snapshot",
            diagnostic: buildDiagnosticSnapshot()
        )

        Task { @MainActor in
            do {
                let imagePayload =
                    try makeCertificationImagePayload(
                        imageURL: imageURL
                    )

                for cycle in 1...certificationCycles {
                    certificationRunnerProgress =
                        "Cycle \(cycle)/\(certificationCycles) · teardown"

                    certificationRecorder.recordEvent(
                        "cycle_started",
                        fields: [
                            "cycle": String(cycle),
                        ]
                    )

                    certificationRecorder.recordEvent(
                        "api_stop_requested",
                        fields: [
                            "cycle": String(cycle),
                            "api_running_before":
                                String(apiServer.isRunning),
                        ]
                    )
                    apiServer.stop()

                    certificationRecorder.recordEvent(
                        "engine_unload_started",
                        fields: [
                            "cycle": String(cycle),
                        ]
                    )
                    await engine.unloadAll()
                    certificationRecorder.recordEvent(
                        "engine_unload_finished",
                        fields: [
                            "cycle": String(cycle),
                        ]
                    )

                    certificationRunnerProgress =
                        "Cycle \(cycle)/\(certificationCycles) · starting API"
                    certificationRecorder.recordEvent(
                        "api_start_requested",
                        fields: [
                            "cycle": String(cycle),
                            "context": "512",
                        ]
                    )

                    // Reuse the actual product OpenAI server setup.
                    startAPIServer()
                    try await waitForCertificationAPIReady(
                        timeoutSeconds: 180
                    )

                    certificationRecorder.recordEvent(
                        "api_ready",
                        fields: [
                            "cycle": String(cycle),
                            "api_running":
                                String(apiServer.isRunning),
                        ]
                    )

                    certificationRunnerProgress =
                        "Cycle \(cycle)/\(certificationCycles) · seed"
                    certificationRecorder.recordEvent(
                        "seed_request_started",
                        fields: [
                            "cycle": String(cycle),
                        ]
                    )
                    let seed =
                        try await performCertificationVisionRequest(
                            imagePayload: imagePayload
                        )
                    certificationRecorder.recordEvent(
                        "seed_request_finished",
                        fields:
                            certificationHTTPFields(
                                cycle: cycle,
                                result: seed
                            )
                    )

                    certificationRunnerProgress =
                        "Cycle \(cycle)/\(certificationCycles) · warm"
                    certificationRecorder.recordEvent(
                        "warm_request_started",
                        fields: [
                            "cycle": String(cycle),
                        ]
                    )
                    let warm =
                        try await performCertificationVisionRequest(
                            imagePayload: imagePayload
                        )
                    certificationRecorder.recordEvent(
                        "warm_request_finished",
                        fields:
                            certificationHTTPFields(
                                cycle: cycle,
                                result: warm
                            )
                    )

                    certificationRecorder.recordSnapshot(
                        label: "cycle_\(cycle)_warm_snapshot",
                        diagnostic: buildDiagnosticSnapshot()
                    )
                    certificationRecorder.recordEvent(
                        "cycle_completed",
                        fields: [
                            "cycle": String(cycle),
                            "warm_http_status":
                                String(warm.statusCode),
                            "warm_completion_tokens":
                                String(warm.completionTokens),
                            "warm_finish_reason":
                                warm.finishReason,
                        ]
                    )
                }

                certificationRunnerProgress =
                    "Finalizing"
                certificationRecorder.recordEvent(
                    "final_api_stop_requested"
                )
                apiServer.stop()
                certificationRecorder.recordEvent(
                    "final_engine_unload_started"
                )
                await engine.unloadAll()
                certificationRecorder.recordEvent(
                    "final_engine_unload_finished"
                )
                certificationRecorder.recordSnapshot(
                    label: "runner_final_snapshot",
                    diagnostic: buildDiagnosticSnapshot()
                )

                _ = certificationRecorder.finishRun(
                    summary:
                        "PASS: completed \(certificationCycles) automated 512-context restart cycles."
                )

                certificationRunnerProgress =
                    "PASS · \(certificationCycles)/\(certificationCycles) cycles"
                status =
                    "Restart Certification 完成，可直接分享单个测试结果"
            } catch {
                certificationRecorder.recordEvent(
                    "runner_failed",
                    fields: [
                        "error":
                            error.localizedDescription,
                    ]
                )
                certificationRecorder.recordSnapshot(
                    label: "runner_failure_snapshot",
                    diagnostic: buildDiagnosticSnapshot()
                )

                apiServer.stop()
                await engine.unloadAll()

                _ = certificationRecorder.finishRun(
                    summary:
                        "FAIL: "
                        + error.localizedDescription
                )

                certificationRunnerProgress =
                    "FAIL · "
                    + error.localizedDescription
                status =
                    "Restart Certification 失败；结果已自动归档"
            }

            certificationRunnerRunning = false
        }
    }

    private func waitForCertificationAPIReady(
        timeoutSeconds: Double
    ) async throws {
        let deadline =
            Date().addingTimeInterval(
                timeoutSeconds
            )

        while Date() < deadline {
            if apiServer.isRunning {
                return
            }

            if !apiServer.lastError.isEmpty {
                throw OpenAIHandlerHTTPError(
                    status: 500,
                    code: "api_start_failed",
                    message: apiServer.lastError
                )
            }

            if status.contains("预热失败") {
                throw OpenAIHandlerHTTPError(
                    status: 500,
                    code: "api_start_failed",
                    message: detail
                )
            }

            try await Task.sleep(
                nanoseconds: 250_000_000
            )
        }

        throw RestartCertificationError.apiReadyTimeout
    }

    private func makeCertificationImagePayload(
        imageURL: URL
    ) throws -> String {
        let scoped =
            imageURL.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                imageURL.stopAccessingSecurityScopedResource()
            }
        }

        let data =
            try Data(contentsOf: imageURL)
        let ext =
            imageURL.pathExtension.lowercased()
        let mime =
            (ext == "jpg" || ext == "jpeg")
                ? "image/jpeg"
                : "image/png"

        return "data:"
            + mime
            + ";base64,"
            + data.base64EncodedString()
    }

    private func performCertificationVisionRequest(
        imagePayload: String
    ) async throws -> RestartCertificationHTTPResult {
        guard
            let url = URL(
                string:
                    "http://127.0.0.1:8080/v1/chat/completions"
            )
        else {
            throw RestartCertificationError
                .invalidLoopbackURL
        }

        let body: [String: Any] = [
            "model": apiServer.modelID,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": imagePayload,
                            ],
                        ],
                        [
                            "type": "text",
                            "text":
                                "Describe the person, the dog, and the background in this image using concise bullet points.",
                        ],
                    ],
                ],
            ],
            "max_completion_tokens": 128,
            "stream": false,
            "reasoning_effort": "none",
        ]

        let bodyData =
            try JSONSerialization.data(
                withJSONObject: body
            )

        var request =
            URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue(
            "application/json; charset=utf-8",
            forHTTPHeaderField:
                "Content-Type"
        )
        request.setValue(
            "Bearer " + apiServer.apiKey,
            forHTTPHeaderField:
                "Authorization"
        )
        request.timeoutInterval = 300

        let started =
            DispatchTime.now().uptimeNanoseconds
        let (data, response) =
            try await URLSession.shared.data(
                for: request
            )
        let ended =
            DispatchTime.now().uptimeNanoseconds

        guard
            let http =
                response as? HTTPURLResponse
        else {
            throw RestartCertificationError
                .invalidHTTPResponse
        }

        guard http.statusCode == 200 else {
            throw RestartCertificationError
                .unexpectedHTTPStatus(
                    http.statusCode
                )
        }

        guard
            let object =
                try JSONSerialization
                    .jsonObject(with: data)
                    as? [String: Any],
            let choices =
                object["choices"]
                    as? [[String: Any]],
            let first = choices.first,
            let finishReason =
                first["finish_reason"]
                    as? String,
            let usage =
                object["usage"]
                    as? [String: Any],
            let completionNumber =
                usage["completion_tokens"]
                    as? NSNumber
        else {
            throw RestartCertificationError
                .malformedResponse
        }

        let elapsedMilliseconds =
            Double(ended - started)
            / 1_000_000

        return RestartCertificationHTTPResult(
            statusCode: http.statusCode,
            elapsedMilliseconds:
                elapsedMilliseconds,
            completionTokens:
                completionNumber.intValue,
            finishReason: finishReason
        )
    }

    private func certificationHTTPFields(
        cycle: Int,
        result: RestartCertificationHTTPResult
    ) -> [String: String] {
        [
            "cycle": String(cycle),
            "http_status":
                String(result.statusCode),
            "elapsed_ms":
                String(
                    format: "%.3f",
                    result.elapsedMilliseconds
                ),
            "completion_tokens":
                String(result.completionTokens),
            "finish_reason":
                result.finishReason,
        ]
    }

    private func startCertificationRecorder() {
        let build =
            Bundle.main.object(
                forInfoDictionaryKey:
                    "CFBundleVersion"
            ) as? String ?? "?"

        let environment: [String: String] = [
            "device": UIDevice.current.model,
            "os":
                UIDevice.current.systemName
                + " "
                + UIDevice.current.systemVersion,
            "physical_memory_mib":
                String(
                    ProcessInfo.processInfo.physicalMemory
                    / 1_048_576
                ),
            "main_model": modelName,
            "vision_tower": mlxVisionWeightsName,
            "runtime_profile": apiRuntimeProfile,
            "api_context_profile": apiContextProfile,
            "vision_prefix_kv_reuse_enabled":
                String(visionPrefixKVReuseEnabled),
        ]

        guard
            certificationRecorder.startRun(
                stage:
                    "RC1.23.6 Certification Recorder",
                build: build,
                environment: environment
            ) != nil
        else {
            return
        }

        certificationRecorder.recordEvent(
            "environment_ready",
            fields: [
                "api_running":
                    String(apiServer.isRunning),
                "status": status,
            ]
        )
        certificationRecorder.recordSnapshot(
            label: "initial_snapshot",
            diagnostic: buildDiagnosticSnapshot()
        )
    }

    private func startAPIServer() {
        guard let selectedModelURL = modelURL else {
            status = "请先选择主模型"
            return
        }

        let selectedMLXVisionWeightsURL =
            mlxVisionWeightsURL
        let selectedRuntime = runtime
        let selectedAPIRuntimeProfile =
            apiRuntimeProfile == "safe"
                ? "safe"
                : "accelerated"
        let selectedAPIContext = 512
        let sharedEngine = engine
        let sharedVisionSidecar = mlxVisionSidecar

        busy = true
        status = "正在预热 RC1.23.6 Frozen 512 Runtime…"
        detail = """
        Text API 继续使用冻结的 RC1.20.7 路径。
        单图请求使用 RC1.23.0 MLX Live Vision Injection；
        不初始化 mmproj，不要求 App 重启。
        """

        Task {
            do {
                await sharedEngine.unloadAll()

                var apiRuntime = selectedRuntime
                apiRuntime.context = selectedAPIContext
                apiRuntime.batch = 8
                apiRuntime.ubatch = 8

                switch selectedAPIRuntimeProfile {
                case "accelerated":
                    apiRuntime.flashAttention = true
                    apiRuntime.offloadKQV = true
                    apiRuntime.opOffload = true
                default:
                    apiRuntime.flashAttention = false
                    apiRuntime.offloadKQV = false
                    apiRuntime.opOffload = false
                }

                apiRuntime.kvUnified = true
                apiRuntime.loadMode = .mmap

                _ = try await sharedEngine.loadModel(
                    url: selectedModelURL,
                    runtime: apiRuntime
                )

                UserDefaults.standard.set(
                    selectedAPIContext,
                    forKey:
                        "BonsaiRC1235ActiveAPIContext"
                )

                UserDefaults.standard.set(
                    selectedAPIRuntimeProfile,
                    forKey:
                        "BonsaiRC1233ActiveAPIRuntimeProfile"
                )

                RC1232PerformanceDiagnostics.beginSession()

                try apiServer.start(port: 8080) {
                    payload,
                    onDelta in

                    let requestID =
                        UUID().uuidString
                    let requestObservation =
                        RC1232PerformanceDiagnostics
                            .beginRequest()
                    let requestStart =
                        requestObservation.start
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
                                    observation:
                                        requestObservation,
                                    route: requestRoute,
                                    stream: payload.stream,
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
                                observation:
                                    requestObservation,
                                stream: payload.stream,
                                packet: packet,
                                metrics: metrics,
                                requestedMaxTokens:
                                    payload.maxTokens,
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
                                    .terminationReason
                                    .openAIFinishReason
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
                            observation:
                                requestObservation,
                            stream: payload.stream,
                            metrics: metrics,
                            requestedMaxTokens:
                                payload.maxTokens,
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
                            metrics.terminationReason
                                .openAIFinishReason
                    )
                }

                await MainActor.run {
                    busy = false
                    status =
                        "RC1.23.6 Frozen 512 Runtime 已预热"
                    let profileText =
                        selectedAPIRuntimeProfile
                            .uppercased()
                    detail =
                        (
                            selectedMLXVisionWeightsURL == nil
                            ? "文本 API 可用；选择 vision_tower.safetensors 后启用单图 MLX 多模态 API。"
                            : "文本 + MLX Live Vision OpenAI API 已就绪。"
                        )
                        + " Runtime Profile="
                        + profileText
                        + " · API Context="
                        + String(selectedAPIContext)
                }
            } catch {
                apiServer.stop()
                await sharedEngine.unloadAll()

                await MainActor.run {
                    busy = false
                    status =
                        "RC1.23.6 Frozen 512 Runtime 预热失败"
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
