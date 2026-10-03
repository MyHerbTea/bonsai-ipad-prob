import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let engine = BonsaiEngine()

    @State private var modelURL: URL?
    @State private var mmprojURL: URL?
    @State private var imageURL: URL?

    @State private var modelName = "尚未选择主模型"
    @State private var mmprojName = "尚未选择 mmproj"
    @State private var imageName = "尚未选择图片"

    @State private var runtime = RuntimeConfig.safe
    @State private var generation: GenerationConfig = {
        var value = GenerationConfig()
        value.maxTokens = 256
        return value
    }()
    @State private var visionPreset = VisionPreset.mid768
    @State private var vision = VisionConfig.mid768
    @State private var visionQuality = VisionQuality.standard
    @State private var answerLengthPreset = AnswerLengthPreset.standard
    @State private var visionInferenceMode = VisionInferenceMode.accelerated
    @State private var showAdvancedVisionTools = false

    @State private var systemPrompt = "You are a helpful assistant"
    @State private var userPrompt = "请用一句话介绍你自己。"
    @State private var visionQuestion = "请描述这张图片的主要内容。"

    @State private var modelReady = false
    @State private var visionReady = false
    @State private var busy = false
    @State private var status = "等待模型"
    @State private var details = ""
    @State private var output = ""
    @State private var systemDiagnosticsText = "尚未读取"

    @State private var showModelImporter = false
    @State private var showMMProjImporter = false
    @State private var showImageImporter = false

    private var lastStage: String {
        UserDefaults.standard.string(forKey: "BonsaiLabLastStage") ?? "无"
    }

    private var engineStage: String {
        let url = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(
            "bonsai_engine_stage.txt"
        )

        guard let text = try? String(
            contentsOf: url,
            encoding: .utf8
        ) else {
            return "无"
        }

        return text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private var mlxVisionStage: String {
        let url = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(
            "bonsai_mlx_vision_stage.txt"
        )

        guard let text = try? String(
            contentsOf: url,
            encoding: .utf8
        ) else {
            return "无"
        }

        return text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private var mlxInjectionStage: String {
        let url = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(
            "bonsai_mlx_injection_stage.txt"
        )

        guard let text = try? String(
            contentsOf: url,
            encoding: .utf8
        ) else {
            return "无"
        }

        return text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private var mlxVisionMetrics: String {
        UserDefaults.standard.string(
            forKey: "BonsaiMLXVisionLastMetrics"
        ) ?? "无"
    }

    private var twoPhaseVisionStage: String {
        let url = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(
            "bonsai_two_phase_vision_stage.txt"
        )

        guard let text = try? String(
            contentsOf: url,
            encoding: .utf8
        ) else {
            return "无"
        }

        return text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private var stagedVisionStage: String {
        let url = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("bonsai_staged_vision_stage.txt")

        guard let text = try? String(
            contentsOf: url,
            encoding: .utf8
        ) else {
            return "无"
        }

        return text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private var stagedFailureHint: String? {
        let stage = stagedVisionStage

        if stage.contains("STAGED_99_PASS") {
            return nil
        }
        if stage.contains("STAGED_02") {
            return "视觉投影器加载失败：确认选择的是匹配 Bonsai 2 的 Q8 mmproj，并保持 mmproj GPU 关闭。"
        }
        if stage.contains("STAGED_03") || stage.contains("STAGED_04") {
            return "图片编码阶段失败：可换一张 JPEG/PNG，或把视觉质量调低后重试。"
        }
        if stage.contains("STAGED_06") {
            return "27B 主模型加载失败：确认使用 PTQ1_0 + MMAP，并关闭其他占用大量内存的 App。"
        }
        if stage.contains("STAGED_07") {
            return "LLM Context 创建失败：先切到“安全”推理模式或降低视觉质量。"
        }
        if stage.contains("STAGED_08") {
            return "视觉 embedding 注入/Prefill 失败：属于多模态解码阶段，可保留诊断信息用于回归。"
        }
        if stage.contains("STAGED_09") {
            return "文本生成阶段失败：降低回答长度或切到“安全”模式后重试。"
        }
        return nil
    }

    private var persistedVisionHeadroom: String {
        let defaults = UserDefaults.standard
        let before = defaults.integer(
            forKey: "BonsaiLabVisionHeadroomBeforeReleaseMiB"
        )
        let afterRelease = defaults.integer(
            forKey: "BonsaiLabVisionHeadroomAfterReleaseMiB"
        )
        let afterMMProj = defaults.integer(
            forKey: "BonsaiLabVisionHeadroomAfterMMProjMiB"
        )
        let afterContext = defaults.integer(
            forKey: "BonsaiLabVisionHeadroomAfterContextMiB"
        )

        guard before > 0 || afterRelease > 0 || afterMMProj > 0 || afterContext > 0 else {
            return "无"
        }

        return "\(before) → \(afterRelease) → \(afterMMProj) → \(afterContext) MiB"
    }

    private var persistedVisionProbe: String {
        let defaults = UserDefaults.standard
        let fileName = defaults.string(
            forKey: "BonsaiLabVisionProbeFileName"
        ) ?? "无"
        let fileSize = defaults.integer(
            forKey: "BonsaiLabVisionProbeFileSizeMiB"
        )
        let before = defaults.integer(
            forKey: "BonsaiLabVisionProbeHeadroomBeforeMiB"
        )
        let after = defaults.integer(
            forKey: "BonsaiLabVisionProbeHeadroomAfterMiB"
        )
        let storedProgress = defaults.integer(
            forKey: "BonsaiLabVisionProbeProgressCode"
        )

        let progressURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("bonsai_mtmd_probe_progress.txt")

        let fileProgress: Int = {
            guard let text = try? String(contentsOf: progressURL, encoding: .utf8) else {
                return storedProgress
            }
            return Int(
                text.trimmingCharacters(in: .whitespacesAndNewlines)
            ) ?? storedProgress
        }()

        guard fileName != "无" || before > 0 || fileProgress != 0 else {
            return "无"
        }

        return "\(fileName), \(fileSize) MiB, headroom=\(before)→\(after) MiB, progress=\(fileProgress)"
    }

    private var persistedCoexistenceProbe: String {
        let defaults = UserDefaults.standard
        let mode = defaults.string(forKey: "BonsaiLabCoexMode") ?? "无"
        let fileName = defaults.string(forKey: "BonsaiLabCoexFileName") ?? "无"
        let fileSize = defaults.integer(forKey: "BonsaiLabCoexFileSizeMiB")
        let before = defaults.integer(forKey: "BonsaiLabCoexHeadroomBeforeMiB")
        let after = defaults.integer(forKey: "BonsaiLabCoexHeadroomAfterMiB")
        let metalBefore = defaults.integer(forKey: "BonsaiLabCoexMetalBeforeMiB")
        let metalAfter = defaults.integer(forKey: "BonsaiLabCoexMetalAfterMiB")
        let metalRecommended = defaults.integer(
            forKey: "BonsaiLabCoexMetalRecommendedMiB"
        )
        let storedProgress = defaults.integer(
            forKey: "BonsaiLabCoexProgressCode"
        )

        let progressURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("bonsai_mtmd_coexist_progress.txt")

        let fileProgress: Int = {
            guard let text = try? String(contentsOf: progressURL, encoding: .utf8) else {
                return storedProgress
            }
            return Int(
                text.trimmingCharacters(in: .whitespacesAndNewlines)
            ) ?? storedProgress
        }()

        guard mode != "无" else {
            return "无"
        }

        let phys = defaults.integer(forKey: "BonsaiLabCoexPhysBeforeMiB")
        let resident = defaults.integer(forKey: "BonsaiLabCoexResidentBeforeMiB")
        let virtual = defaults.integer(forKey: "BonsaiLabCoexVirtualBeforeMiB")
        let extendedVA = defaults.integer(forKey: "BonsaiLabCoexExtendedVA")
        let increased = defaults.integer(forKey: "BonsaiLabCoexIncreasedMemory")
        let loadMode = defaults.string(forKey: "BonsaiLabCoexLoadMode") ?? "?"

        return "\(mode), \(fileName), \(fileSize) MiB, LOAD=\(loadMode), process=\(before)→\(after) MiB, phys=\(phys) MiB, resident=\(resident) MiB, virtual=\(virtual) MiB, Metal=\(metalBefore)→\(metalAfter)/\(metalRecommended) MiB, EVA=\(extendedVA), IML=\(increased), progress=\(fileProgress)"
    }

    private var persistedBootstrap: String {
        let d = UserDefaults.standard
        let start = d.integer(forKey: "BonsaiLabBootstrapHeadroomStartMiB")
        let vocab = d.integer(forKey: "BonsaiLabBootstrapHeadroomAfterVocabMiB")
        let mmproj = d.integer(forKey: "BonsaiLabBootstrapHeadroomAfterMMProjMiB")
        let model = d.integer(forKey: "BonsaiLabBootstrapHeadroomAfterFullModelMiB")
        let context = d.integer(forKey: "BonsaiLabBootstrapHeadroomAfterContextMiB")
        let metalBefore = d.integer(
            forKey: "BonsaiLabBootstrapMetalBeforeContextMiB"
        )
        let metalAfter = d.integer(
            forKey: "BonsaiLabBootstrapMetalAfterContextMiB"
        )
        let recommended = d.integer(
            forKey: "BonsaiLabBootstrapMetalRecommendedMiB"
        )
        let requestedContext = d.integer(
            forKey: "BonsaiLabBootstrapRequestedContext"
        )
        let requestedBatch = d.integer(
            forKey: "BonsaiLabBootstrapRequestedBatch"
        )
        let requestedUBatch = d.integer(
            forKey: "BonsaiLabBootstrapRequestedUBatch"
        )

        guard start > 0 else {
            return "无"
        }

        return "ctx=\(requestedContext)/b\(requestedBatch)/u\(requestedUBatch), headroom=\(start)→\(vocab)→\(mmproj)→\(model)→\(context) MiB, Metal=\(metalBefore)→\(metalAfter)/\(recommended) MiB"
    }

    private var activeVisionPresetName: String {
        if vision == VisionConfig.probe256 {
            return VisionPreset.probe256.displayName
        }
        if vision == VisionConfig.low512 {
            return VisionPreset.low512.displayName
        }
        if vision == VisionConfig.mid768 {
            return VisionPreset.mid768.displayName
        }
        if vision == VisionConfig.full1024 {
            return VisionPreset.full1024.displayName
        }
        return "Custom"
    }

    var body: some View {
        TabView {
            runtimeTab
                .tabItem { Label("运行", systemImage: "cpu") }

            textTab
                .tabItem { Label("文本", systemImage: "text.bubble") }

            visionTab
                .tabItem { Label("视觉", systemImage: "photo") }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                Task {
                    await engine.unloadAll()
                    await MainActor.run {
                        modelReady = false
                        visionReady = false
                        status = "已进入后台，已释放常驻模型"
                    }
                }
            }
        }
    }

    private var runtimeTab: some View {
        NavigationStack {
            Form {
                Section("状态") {
                    LabeledContent("当前状态", value: status)
                    LabeledContent("上次阶段", value: lastStage)
                    LabeledContent("Engine Stage", value: engineStage)
                    LabeledContent(
                        "Two-Phase Vision",
                        value: twoPhaseVisionStage
                    )
                    LabeledContent(
                        "MLX Vision Stage",
                        value: mlxVisionStage
                    )
                    LabeledContent(
                        "Live Vision Injection",
                        value: mlxInjectionStage
                    )
                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        Text("MLX Vision Metrics")
                            .font(.caption.weight(.semibold))
                        Text(mlxVisionMetrics)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("Staged Vision", value: stagedVisionStage)
                    LabeledContent(
                        "Vision 最近可用内存",
                        value: persistedVisionHeadroom
                    )
                    LabeledContent(
                        "mmproj Probe",
                        value: persistedVisionProbe
                    )
                    LabeledContent(
                        "Coexistence Probe",
                        value: persistedCoexistenceProbe
                    )
                    LabeledContent(
                        "Projector-first Bootstrap",
                        value: persistedBootstrap
                    )

                    Text(systemDiagnosticsText)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)

                    Button("刷新签名 / VA / 内存诊断") {
                        refreshSystemDiagnostics()
                    }
                    .disabled(busy)

                    if !details.isEmpty {
                        Text(details)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }

                    if busy {
                        ProgressView("运行中，请保持 App 前台…")
                    }
                }

                Section("主模型") {
                    Text(modelName)
                        .font(.footnote.monospaced())

                    Button("选择主模型 GGUF") {
                        showModelImporter = true
                    }
                    .disabled(busy)
                    .fileImporter(
                        isPresented: $showModelImporter,
                        allowedContentTypes: [
                            UTType(
                                filenameExtension: "gguf",
                                conformingTo: .data
                            )!
                        ],
                        allowsMultipleSelection: false
                    ) { result in
                        switch result {
                        case .success(let urls):
                            guard let url = urls.first else { return }
                            modelURL = url
                            modelName = url.lastPathComponent
                            modelReady = false
                            visionReady = false
                            output = ""
                            status = "已选择主模型"
                            details = url.path

                        case .failure(let error):
                            status = "主模型文件选择失败"
                            details = error.localizedDescription
                        }
                    }
                }

                Section("预设") {
                    HStack {
                        Button("Safe") {
                            runtime = .safe
                        }

                        Button("Text Balanced") {
                            runtime = .textBalanced
                        }

                        Button("Vision Safe") {
                            runtime = .visionSafe
                        }

                        Button("VA Test") {
                            runtime = .safe
                            runtime.gpuLayers = 0
                            runtime.loadMode = .none
                        }

                        Button("Bootstrap CPU") {
                            runtime = .safe
                            runtime.gpuLayers = 0
                            runtime.loadMode = .mmap
                            runtime.kvUnified = true
                        }
                    }

                    Text("Safe = 已验证文本基线。VA Test 已证明 LOAD NONE 在 27B 主模型加载阶段不可行。Bootstrap CPU = MMAP + GPU 0，用于 RC1.7 projector-first 视觉路径。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("运行参数") {
                    intField("Context", value: $runtime.context)
                    intField("Batch", value: $runtime.batch)
                    intField("uBatch", value: $runtime.ubatch)
                    intField("GPU Layers", value: $runtime.gpuLayers)

                    Picker("Model Load Mode", selection: $runtime.loadMode) {
                        ForEach(ModelLoadMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Flash Attention", isOn: $runtime.flashAttention)
                    Toggle("SWA Full", isOn: $runtime.swaFull)
                    Toggle("KV Unified", isOn: $runtime.kvUnified)
                    Toggle("Offload KQV", isOn: $runtime.offloadKQV)
                    Toggle("Op Offload", isOn: $runtime.opOffload)
                    Toggle(
                        "禁用 M5 Metal Tensor API",
                        isOn: $runtime.disableMetalTensorAPI
                    )
                }

                Section {
                    Button(
                        modelReady
                            ? "重新应用配置并重载模型"
                            : "应用配置并加载模型"
                    ) {
                        loadModel()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || modelURL == nil)

                    if modelReady {
                        Button("卸载模型", role: .destructive) {
                            Task {
                                await engine.unloadAll()
                                await MainActor.run {
                                    modelReady = false
                                    visionReady = false
                                    status = "模型已卸载"
                                    details = ""
                                }
                            }
                        }
                        .disabled(busy)
                    }
                }
            }
            .navigationTitle("Bonsai iPad Lab v1 RC1.14")
        }
    }

    private var textTab: some View {
        NavigationStack {
            Form {
                Section("Prompt") {
                    TextField(
                        "System Prompt",
                        text: $systemPrompt,
                        axis: .vertical
                    )
                    .lineLimit(2...5)

                    TextField(
                        "User Prompt",
                        text: $userPrompt,
                        axis: .vertical
                    )
                    .lineLimit(3...10)
                }

                Section("生成参数") {
                    intField("Max Tokens", value: $generation.maxTokens)
                    decimalField("Temperature", value: $generation.temperature)
                    decimalField("Top P", value: $generation.topP)
                    intField("Top K", value: $generation.topK)
                    decimalField("Min P", value: $generation.minP)
                    decimalField(
                        "Repeat Penalty",
                        value: $generation.repeatPenalty
                    )
                    intField("Seed", value: $generation.seed)
                }

                Section {
                    Button("生成文本") {
                        runText()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || !modelReady)
                }

                Section("输出") {
                    if output.isEmpty {
                        Text("尚无输出")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(output)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Text Lab")
        }
    }

    private var visionTab: some View {
        NavigationStack {
            Form {
                Section("模型") {
                    LabeledContent("主模型", value: modelName)
                    Text(mmprojName)
                        .font(.footnote.monospaced())

                    Button("选择视觉 mmproj") {
                        showMMProjImporter = true
                    }
                    .disabled(busy)
                    .fileImporter(
                        isPresented: $showMMProjImporter,
                        allowedContentTypes: [
                            UTType(
                                filenameExtension: "gguf",
                                conformingTo: .data
                            )!
                        ],
                        allowsMultipleSelection: false
                    ) { result in
                        switch result {
                        case .success(let urls):
                            guard let url = urls.first else { return }
                            mmprojURL = url
                            mmprojName = url.lastPathComponent
                            visionReady = false
                            status = "已选择视觉模型"
                            details = ""

                        case .failure(let error):
                            status = "mmproj 文件选择失败"
                            details = error.localizedDescription
                        }
                    }

                    if modelURL == nil {
                        Text("请先在“运行”页选择 PTQ1_0 主模型。Staged Vision 不要求提前加载主模型。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("视觉质量") {
                    Picker(
                        "视觉质量",
                        selection: Binding(
                            get: { visionQuality },
                            set: { quality in
                                visionQuality = quality
                                visionPreset = quality.preset
                                vision = quality.preset.config
                            }
                        )
                    ) {
                        ForEach(VisionQuality.allCases) { quality in
                            Text(quality.label).tag(quality)
                        }
                    }
                    .pickerStyle(.segmented)

                    LabeledContent(
                        "当前",
                        value: visionQuality.note
                    )
                }

                Section("图片与问题") {
                    Text(imageName)
                        .font(.footnote.monospaced())

                    Button("选择图片") {
                        showImageImporter = true
                    }
                    .disabled(busy)
                    .fileImporter(
                        isPresented: $showImageImporter,
                        allowedContentTypes: [.image],
                        allowsMultipleSelection: false
                    ) { result in
                        switch result {
                        case .success(let urls):
                            guard let url = urls.first else { return }
                            imageURL = url
                            imageName = url.lastPathComponent
                            status = "图片已选择"
                            details = ""

                        case .failure(let error):
                            status = "图片选择失败"
                            details = error.localizedDescription
                        }
                    }

                    TextField(
                        "你想问这张图片什么？",
                        text: $visionQuestion,
                        axis: .vertical
                    )
                    .lineLimit(2...8)
                }

                Section("回答") {
                    Picker(
                        "回答长度",
                        selection: Binding(
                            get: { answerLengthPreset },
                            set: { preset in
                                answerLengthPreset = preset
                                generation.maxTokens = preset.maxTokens
                            }
                        )
                    ) {
                        ForEach(AnswerLengthPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)

                    LabeledContent(
                        "最大输出",
                        value: "\(generation.maxTokens) tokens"
                    )

                    Text("同一张图片、同一视觉质量再次提问时，会复用视觉 embedding；完整 27B 也会保持常驻，因此后续提问可同时跳过图片编码和约 4–6 秒的模型重载。App 进入后台时会自动释放常驻模型。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button(
                        busy ? "正在分析…" : "分析图片"
                    ) {
                        runStagedVision()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        busy
                            || modelURL == nil
                            || mmprojURL == nil
                            || imageURL == nil
                            || visionQuestion.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                    )

                    if busy {
                        ProgressView(
                            "本地处理中，请保持 App 在前台"
                        )
                    } else {
                        LabeledContent("状态", value: status)
                    }

                    if let hint = stagedFailureHint,
                       status.localizedCaseInsensitiveContains("fail") {
                        Text(hint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("回答结果") {
                    if output.isEmpty {
                        Text("尚无输出")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(output)
                            .textSelection(.enabled)
                    }
                }

                Section {
                    DisclosureGroup(
                        "高级设置与诊断",
                        isExpanded: $showAdvancedVisionTools
                    ) {
                        Picker(
                            "推理模式",
                            selection: $visionInferenceMode
                        ) {
                            ForEach(VisionInferenceMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        LabeledContent(
                            "当前模式",
                            value: visionInferenceMode.detail
                        )

                        Divider()

                        Picker(
                            "原始视觉预设",
                            selection: Binding(
                                get: { visionPreset },
                                set: { preset in
                                    visionPreset = preset
                                    vision = preset.config
                                    switch preset {
                                    case .low512:
                                        visionQuality = .fast
                                    case .mid768:
                                        visionQuality = .standard
                                    case .full1024:
                                        visionQuality = .detailed
                                    case .probe256:
                                        break
                                    }
                                }
                            )
                        ) {
                            ForEach(VisionPreset.allCases) { preset in
                                Text(preset.shortLabel).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)

                        intField(
                            "Image Max Tokens",
                            value: $vision.imageMaxTokens
                        )
                        intField(
                            "Vision Context",
                            value: $vision.contextTokens
                        )
                        intField(
                            "Vision Batch",
                            value: $vision.contextBatch
                        )
                        intField(
                            "Vision uBatch",
                            value: $vision.contextUBatch
                        )
                        Toggle(
                            "mmproj 使用 GPU",
                            isOn: $vision.useGPU
                        )
                        Toggle(
                            "mmproj Warmup",
                            isOn: $vision.warmup
                        )

                        Divider()

                        LabeledContent(
                            "Native 阶段",
                            value: stagedVisionStage
                        )
                        LabeledContent(
                            "上次阶段",
                            value: lastStage
                        )

                        if !details.isEmpty {
                            Text(details)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }

                        Button("刷新内存诊断") {
                            refreshSystemDiagnostics()
                        }
                        .disabled(busy)

                        if systemDiagnosticsText != "尚未读取" {
                            Text(systemDiagnosticsText)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }

                        Text(
                            "开发者提示：Probe 256 与旧 projector/coexistence 调试路径仍保留在代码中用于回归，但正常使用只走已经验证的 Strata-style staged vision。"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Bonsai Vision")
        }
    }

    private func refreshSystemDiagnostics() {
        Task {
            let diagnostics = await engine.systemDiagnostics()
            await MainActor.run {
                systemDiagnosticsText = diagnostics.summary
            }
        }
    }

    private func loadModel() {
        guard let modelURL else { return }

        busy = true
        output = ""
        status = "正在加载主模型…"
        details = runtime.summary

        Task {
            do {
                let metrics = try await engine.loadModel(
                    url: modelURL,
                    runtime: runtime
                )

                await MainActor.run {
                    busy = false
                    modelReady = true
                    visionReady = false
                    status = "MODEL READY"
                    details = String(
                        format: """
                        Model: %@
                        Size: %.2f GiB
                        Params: %.2f B
                        Load: %.2f s
                        %@
                        """,
                        metrics.description,
                        metrics.sizeGiB,
                        metrics.paramsB,
                        metrics.loadSeconds,
                        metrics.runtimeSummary
                    )
                }
                refreshSystemDiagnostics()
            } catch {
                updateFailure(prefix: "MODEL FAIL", error: error)
            }
        }
    }

    private func loadVisionProjectorFirst() {
        guard let modelURL, let mmprojURL else { return }

        busy = true
        modelReady = false
        visionReady = false
        output = ""
        status = "Projector-first：初始化 vocab-only model…"
        details =
            "runtime: " + runtime.summary
            + "\nmmproj GPU="
            + (vision.useGPU ? "ON" : "OFF")
            + ", image_max_tokens=\(vision.imageMaxTokens)"
            + ", vision_ctx=\(vision.contextTokens)"
            + ", batch=\(vision.contextBatch)"
            + ", ubatch=\(vision.contextUBatch)"
            + ", mode=\(visionInferenceMode.label)"

        Task {
            do {
                let metrics = try await engine.loadVisionProjectorFirst(
                    modelURL: modelURL,
                    mmprojURL: mmprojURL,
                    runtime: runtime,
                    config: vision
                )

                await MainActor.run {
                    busy = false
                    modelReady = true
                    visionReady = true
                    status = "PROJECTOR-FIRST READY"
                    details = metrics.summary
                }
                refreshSystemDiagnostics()
            } catch {
                updateFailure(
                    prefix: "PROJECTOR-FIRST FAIL",
                    error: error
                )
            }
        }
    }

    private func loadVision() {
        guard let mmprojURL else { return }

        busy = true
        status = "正在加载 mmproj…"
        details =
            "image_max_tokens=\(vision.imageMaxTokens), GPU=\(vision.useGPU ? "ON" : "OFF")"

        Task {
            do {
                let metrics = try await engine.loadVision(
                    mmprojURL: mmprojURL,
                    config: vision
                )

                await MainActor.run {
                    busy = false
                    visionReady = true
                    status = "VISION READY"
                    details =
                        "✅ mmproj 已加载，vision capability = YES\n"
                        + metrics.summary
                }
            } catch {
                updateFailure(
                    prefix: "VISION LOAD FAIL",
                    error: error
                )
            }
        }
    }

    private func probeVisionOnly() {
        guard let mmprojURL else { return }

        busy = true
        status = "正在执行 projector-only probe…"
        details = "干净测试：不运行 estimator；卸载主模型，只执行 mtmd_init_from_file(mmproj, text_model=nil)。"

        Task {
            do {
                let metrics = try await engine.probeVisionOnly(
                    mmprojURL: mmprojURL,
                    config: vision
                )

                await MainActor.run {
                    busy = false
                    modelReady = false
                    visionReady = false
                    status = "MMPROJ-ONLY PASS"
                    details = metrics.summary
                }
            } catch {
                await MainActor.run {
                    modelReady = false
                    visionReady = false
                }
                updateFailure(
                    prefix: "MMPROJ-ONLY FAIL",
                    error: error
                )
            }
        }
    }

    private func probeCoexistence(linkTextModel: Bool) {
        guard let mmprojURL else { return }

        busy = true
        let mode = linkTextModel ? "关联 text_model" : "不关联 text_model"
        status = "正在执行共存测试：\(mode)…"
        details =
            "保留主模型权重，释放 Text Context；mmproj GPU="
            + (vision.useGPU ? "ON" : "OFF")

        Task {
            do {
                let metrics = try await engine.probeVisionWithResidentModel(
                    mmprojURL: mmprojURL,
                    config: vision,
                    linkTextModel: linkTextModel
                )

                await MainActor.run {
                    busy = false
                    status = linkTextModel
                        ? "COEX LINKED PASS"
                        : "COEX UNLINKED PASS"
                    details = metrics.summary
                }
            } catch {
                updateFailure(
                    prefix: linkTextModel
                        ? "COEX LINKED FAIL"
                        : "COEX UNLINKED FAIL",
                    error: error
                )
            }
        }
    }

    private func runText() {
        busy = true
        output = ""
        status = "正在生成文本…"
        details = ""

        Task {
            do {
                let metrics = try await engine.generateText(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    generation: generation
                )

                await MainActor.run {
                    busy = false
                    output = metrics.text
                    status = "TEXT PASS"
                    details = metricsText(metrics)
                }
            } catch {
                updateFailure(prefix: "TEXT FAIL", error: error)
            }
        }
    }

    private func runStagedVision() {
        guard
            let modelURL,
            let mmprojURL,
            let imageURL
        else {
            return
        }

        busy = true
        modelReady = false
        visionReady = false
        output = ""
        status = "Staged Vision：正在编码图片…"
        details =
            "这条路径会在进入 LLM Context 前释放 mmproj。\n"
            + "runtime: " + runtime.summary
            + "\nimage_max_tokens=\(vision.imageMaxTokens)"
            + ", ctx=\(vision.contextTokens)"
            + ", batch=\(vision.contextBatch)"
            + ", ubatch=\(vision.contextUBatch)"

        Task {
            do {
                let metrics = try await engine.runStagedVision(
                    modelURL: modelURL,
                    mmprojURL: mmprojURL,
                    imageURL: imageURL,
                    question: visionQuestion,
                    runtime: runtime,
                    vision: vision,
                    generation: generation,
                    inferenceMode: visionInferenceMode
                )

                await MainActor.run {
                    busy = false
                    output = metrics.text
                    status = "STAGED VISION PASS"
                    details = metrics.summary
                }
            } catch {
                updateFailure(
                    prefix: "STAGED VISION FAIL",
                    error: error
                )
            }
        }
    }

    private func runVision() {
        guard let imageURL else { return }

        busy = true
        output = ""
        status = "正在执行视觉问答…"
        details = ""

        Task {
            do {
                let metrics = try await engine.generateVision(
                    imageURL: imageURL,
                    question: visionQuestion,
                    generation: generation
                )

                await MainActor.run {
                    busy = false
                    output = metrics.generation.text
                    status = "VISION PASS"
                    details =
                        metricsText(metrics.generation)
                        + String(
                            format: """
                            
                            Media tokens: %d
                            Vision prefill: %.3f s
                            """,
                            metrics.mediaTokens,
                            metrics.visionPrefillSeconds
                        )
                }
            } catch {
                updateFailure(prefix: "VISION FAIL", error: error)
            }
        }
    }

    private func updateFailure(prefix: String, error: Error) {
        let stage =
            UserDefaults.standard.string(
                forKey: "BonsaiLabLastStage"
            ) ?? "无"

        Task { @MainActor in
            busy = false
            status = prefix
            details =
                error.localizedDescription
                + "\nLast stage: "
                + stage
        }
    }

    private func metricsText(
        _ metrics: GenerationMetrics
    ) -> String {
        String(
            format: """
            Prompt/media tokens: %d
            Generated: %d
            TTFT: %.3f s
            Generation: %.3f s
            Speed: %.2f tok/s
            """,
            metrics.promptTokens,
            metrics.generatedTokens,
            metrics.ttftSeconds,
            metrics.generationSeconds,
            metrics.tokensPerSecond
        )
    }

    private func intField(
        _ title: String,
        value: Binding<Int>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(
                title,
                value: value,
                format: .number
            )
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 120)
        }
    }

    private func decimalField(
        _ title: String,
        value: Binding<Double>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(
                title,
                value: value,
                format: .number.precision(
                    .fractionLength(0...3)
                )
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 120)
        }
    }
}
