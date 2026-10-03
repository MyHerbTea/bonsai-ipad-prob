import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private let engine = UltraSmokeEngine()

    @State private var modelURL: URL?
    @State private var modelName = "尚未选择"
    @State private var profile: SmokeProfile = .metal
    @State private var showImporter = false
    @State private var busy = false
    @State private var engineReady = false
    @State private var status = "等待模型"
    @State private var details = ""
    @State private var output = ""

    private var lastStage: String {
        UserDefaults.standard.string(forKey: "BonsaiUltraSmokeLastStage") ?? "无"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Bonsai 2 · Phase 2.3.1")
                        .font(.largeTitle.bold())

                    Text("Ultra Context · Real Generation")
                        .foregroundStyle(.secondary)

                    GroupBox("上次运行最后阶段") {
                        Text(lastStage)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("模型") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(modelName)
                                .font(.body.monospaced())

                            Button("选择 PTQ1_0 GGUF") {
                                showImporter = true
                            }
                            .disabled(busy)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Profile") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Profile", selection: $profile) {
                                ForEach(SmokeProfile.allCases) { item in
                                    Text(item.rawValue).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text("""
                            n_ctx = 256
                            n_batch = 16
                            n_ubatch = 16
                            max_new_tokens = 16
                            prompt = Hello
                            """)
                            .font(.footnote.monospaced())
                        }
                    }

                    Button("1. 加载模型并创建 Context") {
                        if let url = modelURL {
                            prepare(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || modelURL == nil || engineReady)

                    Button("2. 生成 16 tokens") {
                        smoke()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || !engineReady)

                    if busy {
                        ProgressView("运行中，请保持前台…")
                    }

                    GroupBox("状态") {
                        Text(status + (details.isEmpty ? "" : "\n\n" + details))
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !output.isEmpty {
                        GroupBox("原始输出") {
                            Text(output)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("BonsaiUltraSmoke")
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [
                UTType(filenameExtension: "gguf", conformingTo: .data)!
            ],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                modelURL = url
                modelName = url.lastPathComponent
                engineReady = false
                output = ""
                status = "模型已选择"
                details = "先使用 Ultra Metal。"

            case .failure(let error):
                status = "文件选择失败"
                details = error.localizedDescription
            }
        }
    }

    private func prepare(_ url: URL) {
        busy = true
        engineReady = false
        output = ""
        status = "正在准备 Engine…"
        details = "Profile: \(profile.rawValue)"

        Task {
            do {
                try await engine.prepare(url: url, profile: profile)

                await MainActor.run {
                    busy = false
                    engineReady = true
                    status = "ENGINE READY"
                    details = "✅ 模型 + 256 context 已就绪。"
                }
            } catch {
                let stage =
                    UserDefaults.standard.string(
                        forKey: "BonsaiUltraSmokeLastStage"
                    ) ?? "无"

                await MainActor.run {
                    busy = false
                    engineReady = false
                    status = "PREPARE FAIL"
                    details = """
                    \(error.localizedDescription)

                    Last stage:
                    \(stage)
                    """
                }
            }
        }
    }

    private func smoke() {
        busy = true
        output = ""
        status = "正在执行真实生成…"
        details = "Prompt: Hello"

        Task {
            do {
                let result = try await engine.runSmoke()

                await MainActor.run {
                    busy = false
                    status = "PHASE 2.3 PASS"
                    output = result.output
                    details = String(
                        format: """
                        ✅ PTQ1_0 real decode PASS
                        Generated tokens: %d
                        TTFT: %.3f s
                        Generation time: %.3f s
                        Generation speed: %.2f tok/s
                        Model size: %.2f GiB
                        Parameters: %.2f B
                        """,
                        result.generatedTokens,
                        result.ttftSeconds,
                        result.generationSeconds,
                        result.tokensPerSecond,
                        result.modelSizeGiB,
                        result.paramsB
                    )
                }
            } catch {
                let stage =
                    UserDefaults.standard.string(
                        forKey: "BonsaiUltraSmokeLastStage"
                    ) ?? "无"

                await MainActor.run {
                    busy = false
                    status = "SMOKE FAIL"
                    details = """
                    \(error.localizedDescription)

                    Last stage:
                    \(stage)
                    """
                }
            }
        }
    }
}
