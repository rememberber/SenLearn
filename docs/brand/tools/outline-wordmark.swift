import Foundation
import CoreText
import CoreGraphics

// Convert the brand's exact text into portable, editable SVG glyph outlines.
func number(_ n: CGFloat) -> String { String(format: "%.3f", Double(n)) }
func outlines(_ text: String, _ name: String, _ size: CGFloat) -> [String: Any] {
    let font = CTFontCreateWithName(name as CFString, size, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
    var commands = ""
    for runObject in CTLineGetGlyphRuns(line) as NSArray {
        let run = runObject as! CTRun
        let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
        for i in 0..<count {
            guard let path = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
            let position = positions[i]
            func point(_ p: CGPoint) -> String { "\(number(p.x + position.x)) \(number(-p.y - position.y))" }
            path.applyWithBlock { pointer in
                let e = pointer.pointee
                switch e.type {
                case .moveToPoint: commands += "M\(point(e.points[0])) "
                case .addLineToPoint: commands += "L\(point(e.points[0])) "
                case .addQuadCurveToPoint: commands += "Q\(point(e.points[0])) \(point(e.points[1])) "
                case .addCurveToPoint: commands += "C\(point(e.points[0])) \(point(e.points[1])) \(point(e.points[2])) "
                case .closeSubpath: commands += "Z "
                @unknown default: break
                }
            }
        }
    }
    return ["text": text, "font": CTFontCopyPostScriptName(font) as String, "size": size, "path": commands, "width": CTLineGetTypographicBounds(line, nil, nil, nil)]
}
let output: [String: Any] = ["zh": outlines("森学", "HiraginoSansGB-W6", 170), "en": outlines("SenLearn", "AvenirNext-DemiBold", 94)]
let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
