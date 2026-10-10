import UIKit
import XCTest
@testable import SenLearn

final class PageRotatorTests: XCTestCase {
    func testClockwiseAndCounterclockwiseRotationPreservePixelsAndDimensions() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 120), format: format).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try XCTUnwrap(image.pngData()).write(to: url)
        let originalBytes = try Data(contentsOf: url)
        for turns in [1, -1, 2] {
            let result = try await PageRotator().rotate(imageURL: url, quarterTurns: turns)
            XCTAssertEqual(result.pixelWidth, turns == 2 ? 80 : 120)
            XCTAssertEqual(result.pixelHeight, turns == 2 ? 120 : 80)
            // Sample the red quadrant after rotation to catch mirrors and wrong rotation direction.
            let cgImage = try XCTUnwrap(UIImage(data: result.imageData)?.cgImage)
            let x = turns == -1 ? 20 : result.pixelWidth - 20
            let y = turns == 1 ? 20 : result.pixelHeight - 20
            var pixel = [UInt8](repeating: 0, count: 4)
            let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
                                                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let crop = try XCTUnwrap(cgImage.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            XCTAssertGreaterThan(pixel[0], 240)
            XCTAssertLessThan(pixel[2], 15)
        }
        XCTAssertEqual(try Data(contentsOf: url), originalBytes, "Rotation must not mutate the input file.")
    }
}
