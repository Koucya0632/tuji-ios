import Testing
import UIKit
@testable import Tuji

struct ImageCropTests {
    @Test
    func fixedSquareSelectionProducesSquareUploadBytes() throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100)).jpegData(
            withCompressionQuality: 1
        ) { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        }

        let cropped = try #require(ImageCrop.crop(
            data: source,
            normalizedRect: CGRect(x: 0.25, y: 0, width: 0.5, height: 1)
        ))
        let image = try #require(UIImage(data: cropped))

        #expect(abs(image.size.width - image.size.height) < 0.5)
    }

    @Test
    func invalidImageNeverBecomesUploadBytes() {
        #expect(ImageCrop.prepareProxy(data: Data([0, 1, 2])) == nil)
        #expect(
            ImageCrop.crop(
                data: Data([0, 1, 2]),
                normalizedRect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
            ) == nil
        )
    }
}
