import SwiftUI
import UIKit

/// The image, word geometry, tap testing and accessibility share one zoomed coordinate space.
struct WordPageCanvas: UIViewRepresentable {
    var page: BookPage
    var imageURL: URL
    var selectedID: UUID?
    var color: UIColor
    var reduceMotion: Bool = false
    var onCandidates: ([RecognizedWord]) -> Void

    func makeUIView(context: Context) -> PageScrollView { PageScrollView() }

    func updateUIView(_ view: PageScrollView, context: Context) {
        view.surface.onCandidates = onCandidates
        view.surface.words = page.lines.flatMap(\.words)
        view.surface.selectedID = selectedID
        view.surface.selectionColor = color
        view.reduceMotion = reduceMotion
        if view.pageID != page.id || view.imageURL != imageURL {
            view.imageURL = imageURL
            view.pageID = page.id
            view.surface.image = UIImage(contentsOfFile: imageURL.path)
            view.pageSize = CGSize(width: page.pixelWidth, height: page.pixelHeight)
            view.needsFit = true
            view.setNeedsLayout()
        }
        view.surface.setNeedsDisplay()
        view.surface.refreshAccessibility()
    }
}

final class PageScrollView: UIScrollView, UIScrollViewDelegate {
    let surface = PageSurface()
    var pageID: UUID?
    var imageURL: URL?
    var pageSize: CGSize = .zero
    var needsFit = true
    var reduceMotion = false
    private var previousSize: CGSize = .zero

    init() {
        super.init(frame: .zero)
        delegate = self
        backgroundColor = .clear
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        bouncesZoom = true
        contentInsetAdjustmentBehavior = .never
        addSubview(surface)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        surface.tapRecognizer.require(toFail: doubleTap)
        accessibilityIdentifier = "reader.canvas"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, pageSize.width > 0, pageSize.height > 0 else { return }
        if needsFit || previousSize != bounds.size {
            needsFit = false
            previousSize = bounds.size
            minimumZoomScale = 0.001
            maximumZoomScale = 10
            zoomScale = 1
            surface.frame = CGRect(origin: .zero, size: pageSize)
            contentSize = pageSize
            let fit = min(bounds.width / pageSize.width, bounds.height / pageSize.height)
            minimumZoomScale = fit
            maximumZoomScale = max(fit * 5, 1)
            zoomScale = fit
        }
        centerPage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { surface }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPage() }

    private func centerPage() {
        let insetX = max(0, (bounds.width - contentSize.width) / 2)
        let insetY = max(0, (bounds.height - contentSize.height) / 2)
        let target = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
        if contentInset != target { contentInset = target }
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale * 1.1 {
            setZoomScale(minimumZoomScale, animated: !reduceMotion && !UIAccessibility.isReduceMotionEnabled)
        } else {
            let point = gesture.location(in: surface)
            let scale = min(minimumZoomScale * 2.5, maximumZoomScale)
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: !reduceMotion && !UIAccessibility.isReduceMotionEnabled)
        }
    }
}

final class PageSurface: UIView {
    var image: UIImage?
    var words: [RecognizedWord] = []
    var selectedID: UUID?
    var selectionColor: UIColor = .systemGreen
    var onCandidates: (([RecognizedWord]) -> Void)?
    lazy var tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = UIColor(red: 1, green: 0.992, blue: 0.969, alpha: 1)
        layer.cornerRadius = 10
        clipsToBounds = true
        addGestureRecognizer(tapRecognizer)
        isAccessibilityElement = false
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        image?.draw(in: bounds)
        guard let word = words.first(where: { $0.id == selectedID }) else { return }
        let target = wordRect(word).insetBy(dx: -3, dy: -3)
        let path = UIBezierPath(roundedRect: target, cornerRadius: 7)
        selectionColor.withAlphaComponent(0.17).setFill(); path.fill()
        selectionColor.withAlphaComponent(0.8).setStroke(); path.lineWidth = 2; path.stroke()
    }

    func wordRect(_ word: RecognizedWord) -> CGRect {
        CGRect(x: word.bounds.x * bounds.width, y: word.bounds.y * bounds.height,
               width: word.bounds.width * bounds.width, height: word.bounds.height * bounds.height)
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        let exact = words.filter { wordRect($0).contains(location) }
        if !exact.isEmpty { onCandidates?(exact); return }
        let scale = (superview as? UIScrollView)?.zoomScale ?? 1
        let expansion = 18 / max(scale, 0.01)
        let candidates = words.filter { wordRect($0).insetBy(dx: -expansion, dy: -expansion).contains(location) }
        if !candidates.isEmpty { onCandidates?(candidates) }
    }

    func refreshAccessibility() {
        accessibilityElements = words.map { word in
            let element = WordAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = word.text
            element.accessibilityHint = "点两下听发音"
            element.accessibilityTraits = word.id == selectedID ? [.button, .selected] : [.button]
            element.accessibilityFrameInContainerSpace = wordRect(word)
            element.action = { [weak self] in self?.onCandidates?([word]) }
            return element
        }
    }
    override func layoutSubviews() { super.layoutSubviews(); refreshAccessibility() }
}

final class WordAccessibilityElement: UIAccessibilityElement {
    var action: (() -> Void)?
    override func accessibilityActivate() -> Bool { action?(); return true }
}
