import UIKit

/// Keeps finished strokes in independently invalidatable raster tiles while
/// the active stroke remains a lightweight preview layer.
final class ZLDrawCanvasView: UIView {
    private static let tileLength: CGFloat = 256

    private final class DisplayLinkTarget: NSObject {
        weak var canvas: ZLDrawCanvasView?

        @objc func flush() {
            canvas?.flushPendingInvalidation()
        }
    }

    private final class Tile {
        let rect: CGRect
        let container = UIView()
        let imageView = UIImageView()
        var padding: CGFloat = 0

        var renderRect: CGRect {
            rect.insetBy(dx: -padding, dy: -padding)
        }

        init(rect: CGRect, padding: CGFloat) {
            self.rect = rect
            self.padding = padding
            container.clipsToBounds = true
            imageView.contentMode = .scaleToFill
            container.addSubview(imageView)
        }
    }

    private let previewLayer = CAShapeLayer()
    private let predictedPreviewLayer = CAShapeLayer()
    private var renderSize: CGSize = .zero
    private var tiles: [Tile] = []
    private var tilePadding: CGFloat = 2
    private var pendingInvalidatedPaths: [ZLDrawPath] = []
    private var pendingRenderPaths: [ZLDrawPath] = []
    private var displayLink: CADisplayLink?
    private let displayLinkTarget = DisplayLinkTarget()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        layer.addSublayer(previewLayer)
        layer.addSublayer(predictedPreviewLayer)
        displayLinkTarget.canvas = self
        for previewLayer in [previewLayer, predictedPreviewLayer] {
            previewLayer.anchorPoint = .zero
            previewLayer.position = .zero
            previewLayer.fillColor = UIColor.clear.cgColor
            previewLayer.lineCap = .round
            previewLayer.lineJoin = .round
        }
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        displayLink?.invalidate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutTiles()
        for previewLayer in [previewLayer, predictedPreviewLayer] {
            previewLayer.bounds = bounds
            previewLayer.position = .zero
        }
    }

    func rebuild(paths: [ZLDrawPath], size: CGSize) {
        clearPendingInvalidation()
        renderSize = size
        tilePadding = requiredTilePadding(for: paths)
        previewLayer.path = nil
        predictedPreviewLayer.path = nil
        makeTilesIfNeeded()
        tiles.forEach { render($0, paths: paths) }
    }

    func showPreview(_ path: ZLDrawPath, predictedPath: UIBezierPath? = nil) {
        let scale = displayScale
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        previewLayer.setAffineTransform(transform)
        predictedPreviewLayer.setAffineTransform(transform)
        if path.sampledPointCount == 1 {
            let dot = UIBezierPath(
                arcCenter: path.path.currentPoint,
                radius: path.path.lineWidth / 2,
                startAngle: 0,
                endAngle: .pi * 2,
                clockwise: true
            )
            previewLayer.strokeColor = UIColor.clear.cgColor
            previewLayer.fillColor = path.strokeColor.cgColor
            previewLayer.path = dot.cgPath
        } else {
            previewLayer.strokeColor = path.strokeColor.cgColor
            previewLayer.fillColor = UIColor.clear.cgColor
            previewLayer.lineWidth = path.path.lineWidth
            previewLayer.path = path.path.cgPath
        }
        predictedPreviewLayer.strokeColor = path.strokeColor.cgColor
        predictedPreviewLayer.fillColor = UIColor.clear.cgColor
        predictedPreviewLayer.lineWidth = predictedPath?.lineWidth ?? path.path.lineWidth
        predictedPreviewLayer.path = predictedPath?.cgPath
    }

    func commit(_ path: ZLDrawPath, allPaths: [ZLDrawPath]) {
        flushPendingInvalidation()
        if updateTilePadding(for: allPaths) {
            tiles.forEach { render($0, paths: allPaths) }
            previewLayer.path = nil
            predictedPreviewLayer.path = nil
            return
        }
        for tile in tiles where tile.renderRect.intersects(path.renderBounds) {
            let previous = tile.imageView.image
            tile.imageView.image = image(for: tile.renderRect) { context in
                previous?.draw(in: CGRect(origin: .zero, size: tile.renderRect.size))
                context.translateBy(x: -tile.renderRect.minX, y: -tile.renderRect.minY)
                path.drawPath()
            }
        }
        previewLayer.path = nil
        predictedPreviewLayer.path = nil
    }

    func invalidate(paths: [ZLDrawPath], using allPaths: [ZLDrawPath]) {
        guard !paths.isEmpty else { return }
        for path in paths where !pendingInvalidatedPaths.contains(path) {
            pendingInvalidatedPaths.append(path)
        }
        pendingRenderPaths = allPaths
        scheduleInvalidationFlush()
    }

    func imageSnapshot() -> UIImage? {
        guard renderSize.width > 0, renderSize.height > 0 else { return nil }
        flushPendingInvalidation()
        return UIGraphicsImageRenderer.zl.renderImage(size: renderSize) { context in
            for tile in tiles {
                context.saveGState()
                context.clip(to: tile.rect)
                tile.imageView.image?.draw(in: tile.renderRect)
                context.restoreGState()
            }
        }
    }

    private func makeTilesIfNeeded() {
        guard renderSize.width > 0, renderSize.height > 0 else { return }
        let columns = Int(ceil(renderSize.width / Self.tileLength))
        let rows = Int(ceil(renderSize.height / Self.tileLength))
        guard tiles.count != columns * rows else {
            tiles.forEach { $0.padding = tilePadding }
            layoutTiles()
            return
        }
        tiles.forEach { $0.container.removeFromSuperview() }
        tiles.removeAll(keepingCapacity: true)
        for row in 0..<rows {
            for column in 0..<columns {
                let x = CGFloat(column) * Self.tileLength
                let y = CGFloat(row) * Self.tileLength
                let tile = Tile(
                    rect: CGRect(x: x, y: y, width: min(Self.tileLength, renderSize.width - x), height: min(Self.tileLength, renderSize.height - y)),
                    padding: tilePadding
                )
                insertSubview(tile.container, at: 0)
                tiles.append(tile)
            }
        }
        layoutTiles()
    }

    private func layoutTiles() {
        let scale = displayScale
        for tile in tiles {
            tile.container.frame = CGRect(
                x: tile.rect.minX * scale,
                y: tile.rect.minY * scale,
                width: tile.rect.width * scale,
                height: tile.rect.height * scale
            )
            tile.imageView.frame = CGRect(
                x: -tile.padding * scale,
                y: -tile.padding * scale,
                width: tile.renderRect.width * scale,
                height: tile.renderRect.height * scale
            )
        }
    }

    private func render(_ tile: Tile, paths: [ZLDrawPath]) {
        tile.imageView.image = image(for: tile.renderRect) { context in
            context.translateBy(x: -tile.renderRect.minX, y: -tile.renderRect.minY)
            for path in paths where path.renderBounds.intersects(tile.renderRect) { path.drawPath() }
        }
    }

    private func scheduleInvalidationFlush() {
        guard displayLink == nil else { return }
        let displayLink = CADisplayLink(target: displayLinkTarget, selector: #selector(DisplayLinkTarget.flush))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    private func flushPendingInvalidation() {
        guard !pendingInvalidatedPaths.isEmpty else {
            displayLink?.invalidate()
            displayLink = nil
            return
        }
        let invalidatedPaths = pendingInvalidatedPaths
        let renderPaths = pendingRenderPaths
        clearPendingInvalidation()
        for tile in tiles where invalidatedPaths.contains(where: { $0.renderBounds.intersects(tile.renderRect) }) {
            render(tile, paths: renderPaths)
        }
    }

    private func clearPendingInvalidation() {
        pendingInvalidatedPaths.removeAll(keepingCapacity: true)
        pendingRenderPaths.removeAll(keepingCapacity: true)
        displayLink?.invalidate()
        displayLink = nil
    }

    private func requiredTilePadding(for paths: [ZLDrawPath]) -> CGFloat {
        max(2, paths.map(\.renderPadding).max() ?? 0)
    }

    /// Increasing padding is rare (for example, a client changes to a much
    /// wider brush). Existing tile images then use a different crop, so the
    /// caller rebuilds every tile once with the new shared padding.
    private func updateTilePadding(for paths: [ZLDrawPath]) -> Bool {
        let requiredPadding = requiredTilePadding(for: paths)
        guard requiredPadding > tilePadding else { return false }
        tilePadding = requiredPadding
        tiles.forEach { $0.padding = tilePadding }
        layoutTiles()
        return true
    }

    private func image(for rect: CGRect, actions: (CGContext) -> Void) -> UIImage {
        UIGraphicsImageRenderer.zl.renderImage(size: rect.size) { context in
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            actions(context)
        }
    }

    private var displayScale: CGFloat {
        guard renderSize.width > 0 else { return 1 }
        return bounds.width / renderSize.width
    }
}
