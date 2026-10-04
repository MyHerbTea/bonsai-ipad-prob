import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct FlashNextP0View: View {
    @State private var selectedShardURL: URL?
    @State private var selectedShardName = "尚未选择 model-00008-of-00008.safetensors"
    @State private var showImporter = false
    @State private var isRunning = false
    @State private var log = """
    FlashNext-iPad / Bonsai-Niwaki
    P0-A — Real 3-bit Expert Probe

    当前 App 与 Bonsai 主 App 完全隔离。
    请选择 Niwaki v2.4 的 model-00008-of-00008.safetensors。
    """

    private var safetensorsType: UTType {
        UTType(filenameExtension: "safetensors") ?? .data
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("隔离状态") {
                    LabeledContent("实验线", value: "experiment/flashnext-ipad-p0")
                    LabeledContent("MLX Swift", value: "0.32.3")
                    LabeledContent("Bonsai Runtime", value: "未链接 / 不修改")
                }

                Section("P0-A Asset") {
                    Text(selectedShardName)
                        .font(.footnote)
                        .textSelection(.enabled)

                    Button("选择 Niwaki shard") {
                        showImporter = true
                    }

                    Button(isRunning ? "运行中…" : "运行真实 3-bit Expert Probe") {
                        runProbe()
                    }
                    .disabled(selectedShardURL == nil || isRunning)
                }

                Section("诊断输出") {
                    ScrollView(.horizontal) {
                        Text(log)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 360)

                    Button("复制诊断") {
                        UIPasteboard.general.string = log
                    }
                }
            }
            .navigationTitle("FlashNext P0-A")
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [safetensorsType],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                selectedShardURL = url
                selectedShardName = url.lastPathComponent
                log = """
                Asset selected:
                \(url.lastPathComponent)

                Ready for P0-A.
                """
            case .failure(let error):
                log = "文件选择失败：\(error.localizedDescription)"
            }
        }
    }

    private func runProbe() {
        guard let url = selectedShardURL else { return }

        isRunning = true
        log = """
        === FLASHNEXT IPAD PROBE ===
        phase=P0-A
        status=RUNNING
        asset=\(url.lastPathComponent)
        """

        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try FlashNextExpertProbe.run(shardURL: url)
                }.value
                log = result
            } catch {
                log = """
                === FLASHNEXT IPAD PROBE ===
                phase=P0-A
                asset=\(url.lastPathComponent)
                result=FAIL
                error=\(error.localizedDescription)
                """
            }
            isRunning = false
        }
    }
}
