import Foundation
import ImageIO
import CoreGraphics

struct OpenAIImageInputLimits: Equatable, Sendable {
    let maxEncodedBytes: Int
    let maxDecodedBytes: Int
    let maxPixelCount: Int
    let maxDimension: Int

    static let apiDefault = OpenAIImageInputLimits(
        maxEncodedBytes: 10 * 1_048_576,
        maxDecodedBytes: 8 * 1_048_576,
        maxPixelCount: 24_000_000,
        maxDimension: 8_192
    )
}

struct OpenAIImageInput: Equatable, Sendable {
    let data: Data
    let fileExtension: String
    let width: Int
    let height: Int

    var pixelCount: Int {
        width * height
    }
}

enum OpenAIContentSegment: Equatable, Sendable {
    case text(String)
    case imagePlaceholder
}

enum OpenAIImageOrdering: String, Equatable, Sendable {
    case none
    case imageFirst
    case imageLast
    case interleaved
    case multiple
}

struct OpenAINormalizedContent: Sendable {
    let text: String
    let images: [OpenAIImageInput]
    let segments: [OpenAIContentSegment]
    let ordering: OpenAIImageOrdering

    var imageCount: Int {
        images.count
    }

    var imageData: Data? {
        images.first?.data
    }

    var imageExtension: String {
        images.first?.fileExtension ?? "jpg"
    }
}

enum OpenAIMultimodalError: LocalizedError, Sendable {
    case invalidContentPart
    case invalidImageURL
    case invalidImageData
    case unsupportedImageType(String)
    case remoteImageURLUnsupported
    case tooManyImages
    case imageTooLarge
    case imageDimensionsTooLarge
    case imageDecodeFailed

    var status: Int {
        switch self {
        case .imageTooLarge:
            return 413
        default:
            return 400
        }
    }

    var code: String {
        switch self {
        case .invalidContentPart:
            return "invalid_content_part"
        case .invalidImageURL:
            return "invalid_image_url"
        case .invalidImageData:
            return "invalid_image_data"
        case .unsupportedImageType:
            return "unsupported_image_type"
        case .remoteImageURLUnsupported:
            return "remote_image_url_unsupported"
        case .tooManyImages:
            return "too_many_images"
        case .imageTooLarge:
            return "image_too_large"
        case .imageDimensionsTooLarge:
            return "image_dimensions_too_large"
        case .imageDecodeFailed:
            return "image_decode_failed"
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidContentPart:
            return "消息包含当前 API 不支持或格式无效的 content part。"
        case .invalidImageURL:
            return "图片 image_url 必须是有效的 data:image/...;base64,...。"
        case .invalidImageData:
            return "图片 base64 数据为空或无效。"
        case .unsupportedImageType(let mime):
            return "当前仅支持 PNG 和 JPEG 图片；收到 \(mime)。"
        case .remoteImageURLUnsupported:
            return "RC1.23.1 不下载远程图片；请使用 data:image/...;base64,...。"
        case .tooManyImages:
            return "RC1.25.0 每个请求最多支持三张图片。"
        case .imageTooLarge:
            return "图片编码或解码后的字节数超过本机安全限制。"
        case .imageDimensionsTooLarge:
            return "图片尺寸或总像素数超过本机安全限制。"
        case .imageDecodeFailed:
            return "图片元数据无法解码。"
        }
    }
}

struct OpenAIMessageBindingSummary: Equatable, Sendable {
    let role: String
    let hasText: Bool
    let imageCount: Int
}

enum OpenAIMultimodalMessageBindingValidator {
    static func validate(
        _ messages: [OpenAIMessageBindingSummary]
    ) throws -> Int? {
        var totalImages = 0
        var imageMessageIndices: [Int] = []
        var effectiveUserMessageIndex: Int?

        for (index, message) in messages.enumerated() {
            if message.imageCount > 0
                && message.role != "user" {
                throw OpenAIMultimodalError.invalidContentPart
            }

            totalImages += message.imageCount
            if totalImages > 3 {
                throw OpenAIMultimodalError.tooManyImages
            }

            if message.role == "user", message.hasText {
                effectiveUserMessageIndex = index
            }

            if message.imageCount > 0 {
                imageMessageIndices.append(index)
            }
        }

        if imageMessageIndices.contains(
            where: { $0 != effectiveUserMessageIndex }
        ) {
            throw OpenAIMultimodalError.invalidContentPart
        }

        return imageMessageIndices.last
    }
}

enum OpenAIMultimodalNormalizer {
    static func normalizeContent(
        _ raw: Any?,
        limits: OpenAIImageInputLimits = .apiDefault
    ) throws -> OpenAINormalizedContent {
        if let text = raw as? String {
            return OpenAINormalizedContent(
                text: text,
                images: [],
                segments: [.text(text)],
                ordering: .none
            )
        }

        guard raw != nil else {
            return OpenAINormalizedContent(
                text: "",
                images: [],
                segments: [],
                ordering: .none
            )
        }

        guard let parts = raw as? [[String: Any]] else {
            throw OpenAIMultimodalError.invalidContentPart
        }

        var texts: [String] = []
        var images: [OpenAIImageInput] = []
        var segments: [OpenAIContentSegment] = []
        var imageIndices: [Int] = []

        for part in parts {
            guard let type = part["type"] as? String else {
                throw OpenAIMultimodalError.invalidContentPart
            }

            switch type {
            case "text", "input_text":
                guard let text = part["text"] as? String else {
                    throw OpenAIMultimodalError.invalidContentPart
                }
                texts.append(text)
                segments.append(.text(text))

            case "image_url", "input_image":
                guard images.count < 3 else {
                    throw OpenAIMultimodalError.tooManyImages
                }

                let urlString: String?
                if let object = part["image_url"] as? [String: Any] {
                    urlString = object["url"] as? String
                } else {
                    urlString = part["image_url"] as? String
                }

                guard let urlString, !urlString.isEmpty else {
                    throw OpenAIMultimodalError.invalidImageURL
                }

                let decoded = try decodeDataURL(
                    urlString,
                    limits: limits
                )
                images.append(decoded)
                imageIndices.append(segments.count)
                segments.append(.imagePlaceholder)

            default:
                throw OpenAIMultimodalError.invalidContentPart
            }
        }

        let aggregatePixels = images.reduce(0) {
            partial, image in
            partial + image.pixelCount
        }
        let aggregateBytes = images.reduce(0) {
            partial, image in
            partial + image.data.count
        }

        guard aggregatePixels <= limits.maxPixelCount else {
            throw OpenAIMultimodalError.imageDimensionsTooLarge
        }
        guard aggregateBytes <= limits.maxDecodedBytes else {
            throw OpenAIMultimodalError.imageTooLarge
        }

        let ordering = imageOrdering(
            segments: segments,
            imageIndices: imageIndices
        )

        return OpenAINormalizedContent(
            text: texts.joined(separator: "\n"),
            images: images,
            segments: segments,
            ordering: ordering
        )
    }

    private static func imageOrdering(
        segments: [OpenAIContentSegment],
        imageIndices: [Int]
    ) -> OpenAIImageOrdering {
        guard let imageIndex = imageIndices.first else {
            return .none
        }

        if imageIndices.count > 1 {
            return .multiple
        }

        if imageIndex == 0 {
            return .imageFirst
        }

        if imageIndex == segments.count - 1 {
            return .imageLast
        }

        return .interleaved
    }

    private static func decodeDataURL(
        _ value: String,
        limits: OpenAIImageInputLimits
    ) throws -> OpenAIImageInput {
        if value.hasPrefix("http://")
            || value.hasPrefix("https://") {
            throw OpenAIMultimodalError
                .remoteImageURLUnsupported
        }

        guard value.hasPrefix("data:") else {
            throw OpenAIMultimodalError.invalidImageURL
        }

        guard let comma = value.firstIndex(of: ",") else {
            throw OpenAIMultimodalError.invalidImageURL
        }

        let metaStart = value.index(
            value.startIndex,
            offsetBy: 5
        )
        let meta = String(value[metaStart..<comma])
        let encoded = String(value[value.index(after: comma)...])

        let metadataParts = meta
            .split(separator: ";")
            .map { String($0).lowercased() }

        guard
            let mime = metadataParts.first,
            metadataParts.contains("base64")
        else {
            throw OpenAIMultimodalError.invalidImageURL
        }

        let ext: String
        switch mime {
        case "image/png":
            ext = "png"
        case "image/jpeg", "image/jpg":
            ext = "jpg"
        default:
            throw OpenAIMultimodalError
                .unsupportedImageType(mime)
        }

        guard !encoded.isEmpty else {
            throw OpenAIMultimodalError.invalidImageData
        }

        guard encoded.utf8.count <= limits.maxEncodedBytes else {
            throw OpenAIMultimodalError.imageTooLarge
        }

        guard let data = Data(base64Encoded: encoded) else {
            throw OpenAIMultimodalError.invalidImageData
        }

        guard
            !data.isEmpty,
            data.count <= limits.maxDecodedBytes
        else {
            throw OpenAIMultimodalError.imageTooLarge
        }

        let metadata = try validateImageMetadata(
            data,
            limits: limits
        )

        return OpenAIImageInput(
            data: data,
            fileExtension: ext,
            width: metadata.width,
            height: metadata.height
        )
    }

    private static func validateImageMetadata(
        _ data: Data,
        limits: OpenAIImageInputLimits
    ) throws -> (width: Int, height: Int) {
        guard
            let source = CGImageSourceCreateWithData(
                data as CFData,
                nil
            ),
            let properties =
                CGImageSourceCopyPropertiesAtIndex(
                    source,
                    0,
                    nil
                ) as? [CFString: Any],
            let widthNumber =
                properties[kCGImagePropertyPixelWidth]
                    as? NSNumber,
            let heightNumber =
                properties[kCGImagePropertyPixelHeight]
                    as? NSNumber
        else {
            throw OpenAIMultimodalError.imageDecodeFailed
        }

        let width = widthNumber.intValue
        let height = heightNumber.intValue

        guard width > 0, height > 0 else {
            throw OpenAIMultimodalError.imageDecodeFailed
        }

        guard
            width <= limits.maxDimension,
            height <= limits.maxDimension
        else {
            throw OpenAIMultimodalError
                .imageDimensionsTooLarge
        }

        guard
            height <= limits.maxPixelCount,
            width <= limits.maxPixelCount / height
        else {
            throw OpenAIMultimodalError
                .imageDimensionsTooLarge
        }

        return (width, height)
    }
}
