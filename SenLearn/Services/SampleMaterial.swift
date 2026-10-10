import UIKit

/// A real, locally generated PDF goes through exactly the same import and OCR path as user files.
@MainActor
enum SampleMaterial {
    static func makePDF() throws -> URL {
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 960)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let image = UIImage(named: "forest-lesson")
        let pages = [
            ["The little squirrel lives in the forest.", "It finds a seed under a tree."],
            ["A tiny seed can grow into a big tree.", "The forest is a home for everyone."]
        ]
        let data = renderer.pdfData { context in
            for (index, lines) in pages.enumerated() {
                context.beginPage()
                UIColor(red: 1, green: 0.992, blue: 0.969, alpha: 1).setFill()
                context.cgContext.fill(bounds)
                let ink = UIColor(red: 0.14, green: 0.23, blue: 0.20, alpha: 1)
                ("Forest Friends" as NSString).draw(at: CGPoint(x: 58, y: 28), withAttributes: [
                    .font: UIFont(name: "Georgia", size: 25) ?? .systemFont(ofSize: 25), .foregroundColor: ink
                ])
                image?.draw(in: CGRect(x: 58, y: 78, width: 1084, height: 650))
                for (lineIndex, line) in lines.enumerated() {
                    (line as NSString).draw(at: CGPoint(x: 92, y: 752 + lineIndex * 65), withAttributes: [
                        .font: UIFont(name: "Georgia", size: 47) ?? .systemFont(ofSize: 47), .foregroundColor: ink
                    ])
                }
                ("\(index + 1)" as NSString).draw(at: CGPoint(x: 592, y: 913), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.gray
                ])
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Forest Friends.pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
}
