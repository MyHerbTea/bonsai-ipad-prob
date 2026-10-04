import Foundation

@main
struct RC1250MultiImageComposerContractTests {
    static let pngBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGP8z8DAwMDAxMDAwMDAAAANHQEDasKb6QAAAABJRU5ErkJggg=="

    static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        if !condition() {
            fatalError(message)
        }
    }

    static func makeInput() -> OpenAIImageInput {
        let data = Data(base64Encoded: pngBase64)!
        return OpenAIImageInput(
            data: data,
            fileExtension: "png",
            width: 2,
            height: 2
        )
    }

    static func main() throws {
        let image = makeInput()

        let two = try OpenAIMultiImageComposer.compose(
            [image, image]
        )
        expect(!two.data.isEmpty, "2-image composition empty")
        expect(two.fileExtension == "jpg", "2-image extension changed")
        expect(two.layout == "left-right", "2-image layout changed")

        let three = try OpenAIMultiImageComposer.compose(
            [image, image, image]
        )
        expect(!three.data.isEmpty, "3-image composition empty")
        expect(three.fileExtension == "jpg", "3-image extension changed")
        expect(
            three.layout == "left-center-right",
            "3-image layout changed"
        )

        let twoPrefix =
            OpenAIMultiImageComposer.promptPrefix(imageCount: 2)
        let threePrefix =
            OpenAIMultiImageComposer.promptPrefix(imageCount: 3)
        expect(twoPrefix.contains("image 1"), "2-image prefix missing")
        expect(threePrefix.contains("image 3"), "3-image prefix missing")

        print("RC1.25.0 multi-image composer contracts: PASS")
    }
}
