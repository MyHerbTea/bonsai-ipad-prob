import Foundation
import CoreGraphics
import ImageIO

struct OpenAIMultiImageComposition: Sendable {
    let data: Data
    let fileExtension: String
    let layout: String
}

enum OpenAIMultiImageComposerError: LocalizedError, Sendable {
    case unsupportedImageCount
    case invalidImage(Int)
    case renderFailed
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedImageCount:
            return "多图适配器仅接受 2–3 张图片。"
        case .invalidImage(let index):
            return "第 \(index + 1) 张图片无法安全解码。"
        case .renderFailed:
            return "多图联系表渲染失败。"
        case .encodeFailed:
            return "多图联系表编码失败。"
        }
    }
}

enum OpenAIMultiImageComposer {
    static let canvasWidth = 1_024
    static let canvasHeight = 512
    static let separatorWidth: CGFloat = 4

    static func compose(
        _ images: [OpenAIImageInput]
    ) throws -> OpenAIMultiImageComposition {
        guard (2 ... 3).contains(images.count) else {
            throw OpenAIMultiImageComposerError
                .unsupportedImageCount
        }

        let decoded: [CGImage] = try images
            .enumerated()
            .map { index, input in
                guard
                    let source = CGImageSourceCreateWithData(
                        input.data as CFData,
                        nil
                    )
                else {
                    throw OpenAIMultiImageComposerError
                        .invalidImage(index)
                }

                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways:
                        true,
                    kCGImageSourceCreateThumbnailWithTransform:
                        true,
                    kCGImageSourceThumbnailMaxPixelSize:
                        1_024,
                    kCGImageSourceShouldCacheImmediately:
                        true,
                ]

                guard
                    let image =
                        CGImageSourceCreateThumbnailAtIndex(
                            source,
                            0,
                            options as CFDictionary
                        )
                else {
                    throw OpenAIMultiImageComposerError
                        .invalidImage(index)
                }

                return image
            }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil,
                width: canvasWidth,
                height: canvasHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo:
                    CGImageAlphaInfo
                        .premultipliedLast
                        .rawValue
            )
        else {
            throw OpenAIMultiImageComposerError
                .renderFailed
        }

        let fullRect = CGRect(
            x: 0,
            y: 0,
            width: canvasWidth,
            height: canvasHeight
        )
        context.setFillColor(
            CGColor(
                red: 1,
                green: 1,
                blue: 1,
                alpha: 1
            )
        )
        context.fill(fullRect)

        let cellWidth =
            CGFloat(canvasWidth)
            / CGFloat(decoded.count)

        for (index, image) in decoded.enumerated() {
            let cell = CGRect(
                x: CGFloat(index) * cellWidth,
                y: 0,
                width: cellWidth,
                height: CGFloat(canvasHeight)
            )

            context.saveGState()
            context.clip(to: cell)

            let drawRect = aspectFit(
                image: image,
                in: cell.insetBy(dx: 8, dy: 8)
            )
            context.interpolationQuality = .high
            context.draw(image, in: drawRect)
            context.restoreGState()

            if index > 0 {
                context.setFillColor(
                    CGColor(
                        red: 0.25,
                        green: 0.25,
                        blue: 0.25,
                        alpha: 1
                    )
                )
                context.fill(
                    CGRect(
                        x:
                            CGFloat(index)
                            * cellWidth
                            - separatorWidth / 2,
                        y: 0,
                        width: separatorWidth,
                        height:
                            CGFloat(canvasHeight)
                    )
                )
            }
        }

        guard let rendered = context.makeImage() else {
            throw OpenAIMultiImageComposerError
                .renderFailed
        }

        let output = NSMutableData()
        guard
            let destination =
                CGImageDestinationCreateWithData(
                    output,
                    "public.jpeg" as CFString,
                    1,
                    nil
                )
        else {
            throw OpenAIMultiImageComposerError
                .encodeFailed
        }

        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality:
                0.95
        ]
        CGImageDestinationAddImage(
            destination,
            rendered,
            properties as CFDictionary
        )

        guard CGImageDestinationFinalize(destination) else {
            throw OpenAIMultiImageComposerError
                .encodeFailed
        }

        return OpenAIMultiImageComposition(
            data: Data(referencing: output),
            fileExtension: "jpg",
            layout:
                images.count == 2
                ? "left-right"
                : "left-center-right"
        )
    }

    static func promptPrefix(
        imageCount: Int
    ) -> String {
        switch imageCount {
        case 2:
            return """
            The client supplied 2 images. They are shown in one contact sheet in original request order: image 1 is on the left and image 2 is on the right. Treat them as two distinct images when answering.
            """
        case 3:
            return """
            The client supplied 3 images. They are shown in one contact sheet in original request order: image 1 is on the left, image 2 is in the center, and image 3 is on the right. Treat them as three distinct images when answering.
            """
        default:
            return ""
        }
    }

    private static func aspectFit(
        image: CGImage,
        in rect: CGRect
    ) -> CGRect {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width > 0, height > 0 else {
            return rect
        }

        let scale = min(
            rect.width / width,
            rect.height / height
        )
        let fittedWidth = width * scale
        let fittedHeight = height * scale

        return CGRect(
            x:
                rect.midX
                - fittedWidth / 2,
            y:
                rect.midY
                - fittedHeight / 2,
            width: fittedWidth,
            height: fittedHeight
        )
    }
}
