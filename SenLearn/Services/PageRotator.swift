import UIKit

actor PageRotator {
    func rotate(imageURL: URL, quarterTurns: Int) throws -> ImportedPage {
        try Task.checkCancellation()
        guard let image = UIImage(contentsOfFile: imageURL.path), let source = image.cgImage else {
            throw MaterialImporter.ImportError.invalidImage(1)
        }
        let turns = ((quarterTurns % 4) + 4) % 4
        let original = CGSize(width: source.width, height: source.height)
        let size = turns.isMultiple(of: 2) ? original : CGSize(width: original.height, height: original.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let result = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: CGFloat(turns) * .pi / 2)
            image.draw(in: CGRect(x: -original.width / 2, y: -original.height / 2, width: original.width, height: original.height))
        }
        try Task.checkCancellation()
        // Lossless output avoids compounding JPEG artifacts when a page is rotated again.
        guard let data = result.pngData() else { throw MaterialImporter.ImportError.encodingFailed }
        return ImportedPage(imageData: data, pixelWidth: Int(size.width), pixelHeight: Int(size.height))
    }
}
