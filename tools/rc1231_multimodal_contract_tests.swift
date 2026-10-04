import Foundation

@main
struct RC1231MultimodalContractTests {
    static let pngBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGP8z8DAwMDAxMDAwMDAAAANHQEDasKb6QAAAABJRU5ErkJggg=="

    static let jpegBase64 =
        "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAACAAIDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDi6KKK+ZP3E//Z"

    static func fail(_ message: String) -> Never {
        fatalError(message)
    }

    static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        if !condition() {
            fail(message)
        }
    }

    static func expectError(
        _ code: String,
        _ body: () throws -> Void
    ) {
        do {
            try body()
            fail("Expected error code \(code)")
        } catch let error as OpenAIMultimodalError {
            expect(
                error.code == code,
                "Expected \(code), got \(error.code)"
            )
        } catch {
            fail("Unexpected error type: \(error)")
        }
    }

    static func imagePart(
        _ dataURL: String
    ) -> [String: Any] {
        [
            "type": "image_url",
            "image_url": ["url": dataURL]
        ]
    }

    static func textPart(
        _ text: String
    ) -> [String: Any] {
        [
            "type": "text",
            "text": text
        ]
    }

    static func main() throws {
        let plain = try OpenAIMultimodalNormalizer
            .normalizeContent("hello")
        expect(plain.text == "hello", "plain text changed")
        expect(plain.imageCount == 0, "plain text has image")
        expect(
            plain.segments == [.text("hello")],
            "plain segment mismatch"
        )

        let pngURL =
            "data:image/png;base64," + pngBase64
        let textThenImage = try OpenAIMultimodalNormalizer
            .normalizeContent([
                textPart("describe"),
                imagePart(pngURL),
            ])
        expect(
            textThenImage.imageExtension == "png",
            "PNG extension mismatch"
        )
        expect(
            textThenImage.imageData?.count == 79,
            "PNG bytes mismatch"
        )
        expect(
            textThenImage.segments ==
                [.text("describe"), .imagePlaceholder],
            "text-image ordering lost"
        )
        expect(
            textThenImage.ordering == .imageLast,
            "text-image ordering classification wrong"
        )

        let imageThenText = try OpenAIMultimodalNormalizer
            .normalizeContent([
                imagePart(pngURL),
                textPart("describe"),
            ])
        expect(
            imageThenText.segments ==
                [.imagePlaceholder, .text("describe")],
            "image-text ordering lost"
        )
        expect(
            imageThenText.ordering == .imageFirst,
            "image-first classification wrong"
        )

        let interleaved = try OpenAIMultimodalNormalizer
            .normalizeContent([
                textPart("A"),
                imagePart(pngURL),
                textPart("B"),
            ])
        expect(
            interleaved.segments ==
                [.text("A"), .imagePlaceholder, .text("B")],
            "interleaved ordering lost"
        )
        expect(
            interleaved.text == "A\nB",
            "interleaved text concatenation changed"
        )
        expect(
            interleaved.ordering == .interleaved,
            "interleaved classification wrong"
        )

        let twoImages = try OpenAIMultimodalNormalizer
            .normalizeContent([
                imagePart(pngURL),
                imagePart(pngURL),
                textPart("compare both images"),
            ])
        expect(
            twoImages.imageCount == 2,
            "two-image content should be accepted"
        )
        expect(
            twoImages.ordering == .multiple,
            "two-image ordering should be multiple"
        )

        let threeImages = try OpenAIMultimodalNormalizer
            .normalizeContent([
                imagePart(pngURL),
                imagePart(pngURL),
                imagePart(pngURL),
                textPart("compare all three images"),
            ])
        expect(
            threeImages.imageCount == 3,
            "three-image content should be accepted"
        )
        expect(
            threeImages.ordering == .multiple,
            "three-image ordering should be multiple"
        )

        expectError("too_many_images") {
            _ = try OpenAIMultimodalNormalizer.normalizeContent([
                imagePart(pngURL),
                imagePart(pngURL),
                imagePart(pngURL),
                imagePart(pngURL),
            ])
        }

        expectError("remote_image_url_unsupported") {
            _ = try OpenAIMultimodalNormalizer.normalizeContent([
                imagePart("https://example.com/test.png")
            ])
        }

        expectError("unsupported_image_type") {
            _ = try OpenAIMultimodalNormalizer.normalizeContent([
                imagePart("data:image/gif;base64,R0lGODlhAQABAIAAAAUEBA==")
            ])
        }

        expectError("invalid_image_data") {
            _ = try OpenAIMultimodalNormalizer.normalizeContent([
                imagePart("data:image/png;base64,")
            ])
        }

        expectError("invalid_image_data") {
            _ = try OpenAIMultimodalNormalizer.normalizeContent([
                imagePart("data:image/png;base64,%%%not-base64%%%")
            ])
        }

        let jpeg = try OpenAIMultimodalNormalizer
            .normalizeContent([
                imagePart(
                    "data:image/jpeg;base64," + jpegBase64
                ),
                textPart("what is this?")
            ])
        expect(
            jpeg.imageExtension == "jpg",
            "JPEG extension mismatch"
        )
        expect(
            jpeg.imageData?.count == 633,
            "JPEG bytes mismatch"
        )

        let tinyEncodedLimit = OpenAIImageInputLimits(
            maxEncodedBytes: 16,
            maxDecodedBytes: 1024,
            maxPixelCount: 100,
            maxDimension: 100
        )
        expectError("image_too_large") {
            _ = try OpenAIMultimodalNormalizer.normalizeContent(
                [imagePart(pngURL)],
                limits: tinyEncodedLimit
            )
        }

        let tinyPixelLimit = OpenAIImageInputLimits(
            maxEncodedBytes: 1024,
            maxDecodedBytes: 1024,
            maxPixelCount: 3,
            maxDimension: 100
        )
        expectError("image_dimensions_too_large") {
            _ = try OpenAIMultimodalNormalizer.normalizeContent(
                [imagePart(pngURL)],
                limits: tinyPixelLimit
            )
        }

        expectError("invalid_content_part") {
            _ = try OpenAIMultimodalNormalizer.normalizeContent([
                ["type": "audio_url", "url": "x"]
            ])
        }

        let sameTurnImageIndex = try OpenAIMultimodalMessageBindingValidator.validate([
            OpenAIMessageBindingSummary(
                role: "system",
                hasText: true,
                imageCount: 0
            ),
            OpenAIMessageBindingSummary(
                role: "user",
                hasText: true,
                imageCount: 1
            ),
        ])
        expect(
            sameTurnImageIndex == 1,
            "same-turn image binding changed"
        )

        expectError("invalid_content_part") {
            _ = try OpenAIMultimodalMessageBindingValidator.validate([
                OpenAIMessageBindingSummary(
                    role: "user",
                    hasText: true,
                    imageCount: 1
                ),
                OpenAIMessageBindingSummary(
                    role: "assistant",
                    hasText: true,
                    imageCount: 0
                ),
                OpenAIMessageBindingSummary(
                    role: "user",
                    hasText: true,
                    imageCount: 0
                ),
            ])
        }

        expectError("invalid_content_part") {
            _ = try OpenAIMultimodalMessageBindingValidator.validate([
                OpenAIMessageBindingSummary(
                    role: "user",
                    hasText: true,
                    imageCount: 0
                ),
                OpenAIMessageBindingSummary(
                    role: "user",
                    hasText: false,
                    imageCount: 1
                ),
            ])
        }

        expectError("invalid_content_part") {
            _ = try OpenAIMultimodalMessageBindingValidator.validate([
                OpenAIMessageBindingSummary(
                    role: "assistant",
                    hasText: true,
                    imageCount: 1
                ),
            ])
        }

        let threeImageTurn =
            try OpenAIMultimodalMessageBindingValidator
                .validate([
                    OpenAIMessageBindingSummary(
                        role: "system",
                        hasText: true,
                        imageCount: 0
                    ),
                    OpenAIMessageBindingSummary(
                        role: "user",
                        hasText: true,
                        imageCount: 3
                    ),
                ])
        expect(
            threeImageTurn == 1,
            "three-image effective user turn changed"
        )

        expectError("too_many_images") {
            _ = try OpenAIMultimodalMessageBindingValidator.validate([
                OpenAIMessageBindingSummary(
                    role: "user",
                    hasText: true,
                    imageCount: 4
                ),
            ])
        }

        print("RC1.23.1 multimodal parser contracts: PASS")
    }
}
