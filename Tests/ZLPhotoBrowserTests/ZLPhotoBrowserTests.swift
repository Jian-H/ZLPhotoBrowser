import XCTest
@testable import ZLPhotoBrowser

final class ZLPhotoBrowserTests: XCTestCase {
    func testSingleSampleRendersAsDot() {
        let path = makePath(start: CGPoint(x: 20, y: 20))
        let image = render(path: path, size: CGSize(width: 40, height: 40))

        XCTAssertGreaterThan(alpha(in: image, at: CGPoint(x: 20, y: 20)), 0)
    }

    func testSingleSampleCanBeHitByEraser() {
        let path = makePath(start: CGPoint(x: 20, y: 20))

        XCTAssertTrue(path.hitTest(CGPoint(x: 20, y: 20), extraRadius: 4))
    }

    func testDenseSamplesAreRetainedAndReachTrueEndpoint() throws {
        let path = makePath(start: CGPoint(x: 10, y: 10))
        let samples = [
            CGPoint(x: 10.02, y: 10.01),
            CGPoint(x: 10.04, y: 10.02),
            CGPoint(x: 10.08, y: 10.04),
            CGPoint(x: 10.16, y: 10.08),
        ]
        samples.forEach { path.addLine(to: $0) }
        let endpoint = try XCTUnwrap(samples.last)

        XCTAssertEqual(path.sampledPointCount, samples.count + 1)
        XCTAssertEqual(path.path.currentPoint.x, endpoint.x, accuracy: 0.0001)
        XCTAssertEqual(path.path.currentPoint.y, endpoint.y, accuracy: 0.0001)
    }

    func testTileSnapshotKeepsCrossBoundaryStrokeAndInvalidatesLocally() throws {
        let canvas = ZLDrawCanvasView(frame: CGRect(x: 0, y: 0, width: 600, height: 600))
        canvas.layoutIfNeeded()
        canvas.rebuild(paths: [], size: CGSize(width: 600, height: 600))

        let path = makePath(start: CGPoint(x: 252, y: 128))
        path.addLine(to: CGPoint(x: 260, y: 128))
        path.finishDrawing()
        canvas.commit(path, allPaths: [path])

        let committed = try XCTUnwrap(canvas.imageSnapshot())
        XCTAssertGreaterThan(alpha(in: committed, at: CGPoint(x: 256, y: 128)), 0)

        canvas.invalidate(paths: [path], using: [])
        let invalidated = try XCTUnwrap(canvas.imageSnapshot())
        XCTAssertEqual(alpha(in: invalidated, at: CGPoint(x: 256, y: 128)), 0)
    }

    func testDrawStrokeSessionPreservesEveryActualPointAndSeparatesPredictions() {
        let start = CGPoint(x: 10, y: 10)
        let actual = [CGPoint(x: 10.2, y: 10.1), CGPoint(x: 11, y: 10.5)]
        let predicted = [CGPoint(x: 12, y: 11)]
        let session = ZLDrawStrokeSession(actualPoints: [start])

        XCTAssertEqual(Array(session.takeUnrenderedActualPoints()), [start])
        session.append(actualPoints: actual, predictedPoints: predicted)

        XCTAssertEqual(Array(session.takeUnrenderedActualPoints()), actual)
        XCTAssertEqual(session.predictedPoints, predicted)
        session.clearPredictedPoints()
        XCTAssertTrue(session.predictedPoints.isEmpty)
    }

    func testDrawStrokeSessionReplaysAShortStrokeIntoItsPath() {
        let start = CGPoint(x: 10, y: 10)
        let end = CGPoint(x: 14, y: 13)
        let session = ZLDrawStrokeSession(actualPoints: [start])
        let path = makePath(start: start)
        _ = session.takeUnrenderedActualPoints()
        session.append(actualPoints: [CGPoint(x: 12, y: 11), end], predictedPoints: [])
        path.addLines(session.takeUnrenderedActualPoints())

        XCTAssertEqual(path.sampledPointCount, 3)
        XCTAssertEqual(path.path.currentPoint, end)
    }

    func testDrawStrokeSessionHasNoPendingPointsForAnEmptyBatch() {
        let session = ZLDrawStrokeSession(actualPoints: [])

        XCTAssertTrue(session.takeUnrenderedActualPoints().isEmpty)
    }

    func testEraserTouchEligibilityRejectsTheButtonExpandedHitArea() {
        let eraserButton = ZLEnlargeButton(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
        eraserButton.enlargeInset = 30

        XCTAssertTrue(
            ZLEditImageViewController.isPointInsideDrawControl(
                CGPoint(x: -10, y: 18),
                control: eraserButton
            )
        )
    }

    func testDrawTouchEligibilityRejectsColorCollectionViewArea() {
        let colorCollectionView = UIView(frame: CGRect(x: 0, y: 0, width: 240, height: 50))

        XCTAssertTrue(
            ZLEditImageViewController.isPointInsideDrawControl(
                CGPoint(x: 120, y: 25),
                control: colorCollectionView
            )
        )
    }

    func testCanvasPreviewShowsTheInitialDotBeforeAStrokeMoves() {
        let canvas = ZLDrawCanvasView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        canvas.layoutIfNeeded()
        canvas.rebuild(paths: [], size: CGSize(width: 40, height: 40))

        let path = makePath(start: CGPoint(x: 20, y: 20))
        canvas.showPreview(path)

        let image = UIGraphicsImageRenderer(size: canvas.bounds.size).image { context in
            canvas.layer.render(in: context.cgContext)
        }
        XCTAssertGreaterThan(alpha(in: image, at: CGPoint(x: 20, y: 20)), 0)
    }

    static var allTests = [
        ("testSingleSampleRendersAsDot", testSingleSampleRendersAsDot),
        ("testSingleSampleCanBeHitByEraser", testSingleSampleCanBeHitByEraser),
        ("testDenseSamplesAreRetainedAndReachTrueEndpoint", testDenseSamplesAreRetainedAndReachTrueEndpoint),
        ("testTileSnapshotKeepsCrossBoundaryStrokeAndInvalidatesLocally", testTileSnapshotKeepsCrossBoundaryStrokeAndInvalidatesLocally),
        ("testDrawStrokeSessionPreservesEveryActualPointAndSeparatesPredictions", testDrawStrokeSessionPreservesEveryActualPointAndSeparatesPredictions),
        ("testDrawStrokeSessionReplaysAShortStrokeIntoItsPath", testDrawStrokeSessionReplaysAShortStrokeIntoItsPath),
        ("testDrawStrokeSessionHasNoPendingPointsForAnEmptyBatch", testDrawStrokeSessionHasNoPendingPointsForAnEmptyBatch),
        ("testEraserTouchEligibilityRejectsTheButtonExpandedHitArea", testEraserTouchEligibilityRejectsTheButtonExpandedHitArea),
        ("testDrawTouchEligibilityRejectsColorCollectionViewArea", testDrawTouchEligibilityRejectsColorCollectionViewArea),
        ("testCanvasPreviewShowsTheInitialDotBeforeAStrokeMoves", testCanvasPreviewShowsTheInitialDotBeforeAStrokeMoves),
    ]

    private func makePath(start: CGPoint) -> ZLDrawPath {
        ZLDrawPath(
            pathColor: .red,
            pathWidth: 8,
            defaultLinePath: 8,
            ratio: 1,
            startPoint: start
        )
    }

    private func render(path: ZLDrawPath, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            path.drawPath()
        }
    }

    private func alpha(in image: UIImage, at point: CGPoint) -> UInt8 {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let sampled = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
        }
        guard let image = sampled.cgImage,
              let pixel = image.cropping(to: CGRect(x: point.x, y: point.y, width: 1, height: 1)) else {
            return 0
        }
        var bytes = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )
        context?.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return bytes[3]
    }
}
