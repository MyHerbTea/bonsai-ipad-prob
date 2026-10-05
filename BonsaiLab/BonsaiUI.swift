import SwiftUI
import UIKit
import ImageIO

// Use native split navigation so iPad window resizing and compact layouts stay system managed.
enum BonsaiDestination: String, CaseIterable, Identifiable {
    case vision = "视觉问答"
    case models = "模型管理"
    case api = "本地 API"
    case diagnostics = "高级与诊断"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .vision: return "bubble.left.and.text.bubble.right"
        case .models: return "square.stack.3d.up"
        case .api: return "network"
        case .diagnostics: return "slider.horizontal.3"
        }
    }
}

struct BonsaiCanvas: View {
    var body: some View {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
    }
}

struct BonsaiPanel<Content: View>: View {
    let title: String
    let systemImage: String
    private let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct BonsaiStatusBadge: View {
    let title: String
    let active: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(active ? Color.teal : Color.secondary)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

struct BonsaiControlSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(uiColor: .secondarySystemGroupedBackground),
                               in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        } else {
            // SDK guard keeps this source buildable with the project's older Xcode runners.
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular, in: .rect(cornerRadius: 26))
            } else {
                materialSurface(content)
            }
            #else
            materialSurface(content)
            #endif
        }
    }

    private func materialSurface(_ content: Content) -> some View {
        content
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator).opacity(0.2), lineWidth: 0.5)
            }
    }
}

struct BonsaiEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.teal)
                .frame(width: 76, height: 76)
                .background(Color.teal.opacity(0.08), in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

struct BonsaiImagePreview: View {
    let url: URL?
    let fileName: String
    @State private var preview: UIImage?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 12) {
            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("参考图片：" + fileName)
            } else if isLoading {
                ProgressView("正在载入预览")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "photo")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.teal)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(url == nil ? "添加一张图片" : "图片已选择")
                            .font(.headline)
                        Text(url == nil ? "从“文件”中选择你想探索的图片" : "此格式无法显示缩略预览，可继续提问。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 16)
            }
            if url != nil {
                Text(fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: url) {
            preview = nil
            isLoading = false
            guard let url else { return }
            isLoading = true
            let thumbnailTask = Task.detached(priority: .userInitiated) {
                Self.thumbnailData(for: url)
            }
            let data = await thumbnailTask.value
            guard !Task.isCancelled else { return }
            preview = data.flatMap { UIImage(data: $0) }
            isLoading = false
        }
    }

    // Decode a bounded thumbnail off the main actor, rather than loading a full-resolution image.
    private nonisolated static func thumbnailData(for url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 960,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { return nil }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return data as Data
        }
    }
}
