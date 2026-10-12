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

    func testDrawTouchEligibilityRejectsEditToolCollectionViewArea() {
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let editToolCollectionView = UIView(frame: CGRect(x: 20, y: 490, width: 240, height: 30))
        rootView.addSubview(editToolCollectionView)

        XCTAssertTrue(
            ZLEditImageViewController.isPointInsideAnyDrawControl(
                CGPoint(x: 40, y: 505),
                in: rootView,
                controls: [editToolCollectionView]
            )
        )
    }

    func testDrawGestureIsAvailableAfterZoomEnds() {
        XCTAssertFalse(
            ZLEditImageViewController.shouldBlockDrawing(
                scrollPanState: .possible,
                pinchState: .ended,
                isDecelerating: false
            )
        )
    }

    func testSingleFingerDrawingHasPriorityOverScrollPanAfterZoom() {
        XCTAssertFalse(
            ZLEditImageViewController.shouldBlockDrawing(
                scrollPanState: .changed,
                pinchState: .possible,
                isDecelerating: false
            )
        )
    }

    func testDrawGestureIsBlockedWhilePinching() {
        XCTAssertTrue(
            ZLEditImageViewController.shouldBlockDrawing(
                scrollPanState: .possible,
                pinchState: .changed,
                isDecelerating: false,
            )
        )
    }

    func testDrawTouchCollectorOnlyFinishesWhenTheTrackedTouchEnds() {
        XCTAssertFalse(
            ZLDrawTouchCollector.shouldFinishTracking(
                hasCollectedTouch: true,
                collectedTouchIsEnding: false
            )
        )
        XCTAssertTrue(
            ZLDrawTouchCollector.shouldFinishTracking(
                hasCollectedTouch: true,
                collectedTouchIsEnding: true
            )
        )
    }

    func testDrawTouchCollectorCancelsTrackingWhenAnotherTouchBegins() {
        XCTAssertEqual(
            ZLDrawTouchCollector.beginAction(
                hasCollectedTouch: true,
                activeTouchCount: 2
            ),
            .cancelTracking
        )
    }

    func testDrawTouchCollectorRejectsMultiTouchWhenNoTouchIsTracked() {
        XCTAssertEqual(
            ZLDrawTouchCollector.beginAction(
                hasCollectedTouch: false,
                activeTouchCount: 2
            ),
            .reject
        )
    }

    func testDrawLineWidthDoesNotChangeWithImageZoomScale() {
        let configuredWidth: CGFloat = 6

        XCTAssertEqual(
            ZLEditImageViewController.effectiveDrawLineWidth(
                configuredWidth: configuredWidth,
                zoomScale: 1
            ),
            configuredWidth
        )
        XCTAssertEqual(
            ZLEditImageViewController.effectiveDrawLineWidth(
                configuredWidth: configuredWidth,
                zoomScale: 3
            ),
            configuredWidth
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

    func testCanvasCanDiscardAnActivePreviewWithoutCommittingIt() {
        let canvas = ZLDrawCanvasView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        canvas.layoutIfNeeded()
        canvas.rebuild(paths: [], size: CGSize(width: 40, height: 40))

        canvas.showPreview(makePath(start: CGPoint(x: 20, y: 20)))
        canvas.clearPreview()

        let image = UIGraphicsImageRenderer(size: canvas.bounds.size).image { context in
            canvas.layer.render(in: context.cgContext)
        }
        XCTAssertEqual(alpha(in: image, at: CGPoint(x: 20, y: 20)), 0)
    }

    func testEditorTapGestureRejectsTopButtonsIncludingExpandedHitAreas() {
        let editor = makeEditor()
        let tap = LocatedTapGestureRecognizer()
        for button in [editor.cancelBtn, editor.undoBtn, editor.redoBtn] {
            tap.testLocation = editor.view.convert(
                CGPoint(x: -4, y: button.bounds.midY),
                from: button
            )
            XCTAssertFalse(editor.gestureRecognizerShouldBegin(tap))
        }
    }

    func testEditorDrawingPanRejectsToolbarButtons() throws {
        let editor = makeEditor()
        let collectionView = try XCTUnwrap(editor.bottomShadowView.subviews.compactMap { $0 as? UICollectionView }.first)
        let drawIndex = try XCTUnwrap(ZLPhotoConfiguration.default().editImageConfiguration.tools.firstIndex(of: .draw))
        editor.collectionView(collectionView, didSelectItemAt: IndexPath(item: drawIndex, section: 0))
        let pan = LocatedPanGestureRecognizer()
        for button in [editor.cancelBtn, editor.undoBtn, editor.redoBtn, editor.eraserBtn, editor.doneBtn] {
            pan.testLocation = editor.view.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
            XCTAssertFalse(editor.gestureRecognizerShouldBegin(pan))
        }
        pan.testLocation = CGPoint(x: 160, y: 320)
        XCTAssertTrue(editor.gestureRecognizerShouldBegin(pan))
    }

    func testDrawingCollectorAndRootGesturesRejectButtonTouchesAtTouchDown() throws {
        let editor = makeEditor()
        let collectionView = try XCTUnwrap(editor.bottomShadowView.subviews.compactMap { $0 as? UICollectionView }.first)
        let drawIndex = try XCTUnwrap(ZLPhotoConfiguration.default().editImageConfiguration.tools.firstIndex(of: .draw))
        editor.collectionView(collectionView, didSelectItemAt: IndexPath(item: drawIndex, section: 0))
        editor.mainScrollView.zoomScale = 2
        let gestures = try XCTUnwrap(editor.view.gestureRecognizers)
        let collector = try XCTUnwrap(gestures.compactMap { $0 as? ZLDrawTouchCollector }.first)
        XCTAssertTrue(collector.delegate === editor)
        let touch = LocatedTouch(referenceView: editor.view)

        for button in [editor.cancelBtn, editor.undoBtn, editor.redoBtn, editor.eraserBtn, editor.doneBtn] {
            touch.testLocation = editor.view.convert(
                CGPoint(x: button.bounds.midX, y: button.bounds.midY), from: button
            )
            for gesture in gestures {
                XCTAssertFalse(editor.gestureRecognizer(gesture, shouldReceive: touch))
            }
            XCTAssertFalse(collector.shouldCollect?(touch) ?? true)
        }
        touch.testLocation = CGPoint(x: 160, y: 320)
        XCTAssertTrue(collector.shouldCollect?(touch) ?? false)
    }

    func testDrawControlEligibilityIncludesExpandedHitArea() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let button = ZLEnlargeButton(frame: CGRect(x: 260, y: 40, width: 30, height: 30))
        button.enlargeInset = 8
        root.addSubview(button)

        XCTAssertTrue(ZLEditImageViewController.isPointInsideAnyDrawControl(
            CGPoint(x: 256, y: 55), in: root, controls: [button]
        ))
    }

    func testDrawControlEligibilityIgnoresHiddenToolbar() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let toolbar = UIView(frame: root.bounds)
        let button = ZLEnlargeButton(frame: CGRect(x: 260, y: 40, width: 30, height: 30))
        root.addSubview(toolbar)
        toolbar.addSubview(button)
        toolbar.alpha = 0

        XCTAssertFalse(ZLEditImageViewController.isPointInsideAnyDrawControl(
            CGPoint(x: 275, y: 55), in: root, controls: [button]
        ))
    }

    func testToolbarRoutesExpandedButtonHitAreaToButton() {
        let toolbar = ZLPassThroughView(frame: CGRect(x: 0, y: 0, width: 320, height: 150))
        let button = ZLEnlargeButton(frame: CGRect(x: 260, y: 40, width: 30, height: 30))
        button.enlargeInset = 8
        toolbar.addSubview(button)
        let underlyingSticker = UIView(frame: toolbar.bounds)
        toolbar.findResponderSticker = { _ in underlyingSticker }

        XCTAssertTrue(toolbar.hitTest(CGPoint(x: 256, y: 55), with: nil) === button)
    }

    func testUndoRedoButtonsRestoreDrawingAndUpdateEnabledState() throws {
        let path = makePath(start: CGPoint(x: 20, y: 20))
        path.finishDrawing()
        let editor = makeEditor(editModel: ZLEditImageModel(drawPaths: [path], actions: [.draw(path)]))

        let canvas = try XCTUnwrap(editor.mainScrollView.subviews.flatMap { $0.subviews }.compactMap { $0 as? ZLDrawCanvasView }.first)
        let initialImage = try XCTUnwrap(canvas.imageSnapshot())
        XCTAssertGreaterThan(alpha(in: initialImage, at: CGPoint(x: 20, y: 20)), 0)
        XCTAssertTrue(editor.undoBtn.isEnabled)
        XCTAssertFalse(editor.redoBtn.isEnabled)
        let undoAction = try XCTUnwrap(editor.undoBtn.actions(forTarget: editor, forControlEvent: .touchUpInside)?.first)
        editor.perform(NSSelectorFromString(undoAction))
        XCTAssertFalse(editor.undoBtn.isEnabled)
        XCTAssertTrue(editor.redoBtn.isEnabled)
        let undoneImage = try XCTUnwrap(canvas.imageSnapshot())
        XCTAssertEqual(alpha(in: undoneImage, at: CGPoint(x: 20, y: 20)), 0)
        let redoAction = try XCTUnwrap(editor.redoBtn.actions(forTarget: editor, forControlEvent: .touchUpInside)?.first)
        editor.perform(NSSelectorFromString(redoAction))
        XCTAssertTrue(editor.undoBtn.isEnabled)
        XCTAssertFalse(editor.redoBtn.isEnabled)
        let redoneImage = try XCTUnwrap(canvas.imageSnapshot())
        XCTAssertGreaterThan(alpha(in: redoneImage, at: CGPoint(x: 20, y: 20)), 0)
    }

    private func makeEditor(editModel: ZLEditImageModel? = nil) -> ZLEditImageViewController {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 640), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 640))
        }
        let editor = ZLEditImageViewController(image: image, editModel: editModel)
        editor.loadViewIfNeeded()
        editor.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        editor.view.setNeedsLayout()
        editor.view.layoutIfNeeded()
        return editor
    }

    static var allTests = [
        ("testDrawingCollectorAndRootGesturesRejectButtonTouchesAtTouchDown", testDrawingCollectorAndRootGesturesRejectButtonTouchesAtTouchDown),
        ("testEditorTapGestureRejectsTopButtonsIncludingExpandedHitAreas", testEditorTapGestureRejectsTopButtonsIncludingExpandedHitAreas),
        ("testEditorDrawingPanRejectsToolbarButtons", testEditorDrawingPanRejectsToolbarButtons),
        ("testDrawControlEligibilityIncludesExpandedHitArea", testDrawControlEligibilityIncludesExpandedHitArea),
        ("testDrawControlEligibilityIgnoresHiddenToolbar", testDrawControlEligibilityIgnoresHiddenToolbar),
        ("testToolbarRoutesExpandedButtonHitAreaToButton", testToolbarRoutesExpandedButtonHitAreaToButton),
        ("testUndoRedoButtonsRestoreDrawingAndUpdateEnabledState", testUndoRedoButtonsRestoreDrawingAndUpdateEnabledState),
        ("testSingleSampleRendersAsDot", testSingleSampleRendersAsDot),
        ("testSingleSampleCanBeHitByEraser", testSingleSampleCanBeHitByEraser),
        ("testDenseSamplesAreRetainedAndReachTrueEndpoint", testDenseSamplesAreRetainedAndReachTrueEndpoint),
        ("testTileSnapshotKeepsCrossBoundaryStrokeAndInvalidatesLocally", testTileSnapshotKeepsCrossBoundaryStrokeAndInvalidatesLocally),
        ("testDrawStrokeSessionPreservesEveryActualPointAndSeparatesPredictions", testDrawStrokeSessionPreservesEveryActualPointAndSeparatesPredictions),
        ("testDrawStrokeSessionReplaysAShortStrokeIntoItsPath", testDrawStrokeSessionReplaysAShortStrokeIntoItsPath),
        ("testDrawStrokeSessionHasNoPendingPointsForAnEmptyBatch", testDrawStrokeSessionHasNoPendingPointsForAnEmptyBatch),
        ("testEraserTouchEligibilityRejectsTheButtonExpandedHitArea", testEraserTouchEligibilityRejectsTheButtonExpandedHitArea),
        ("testDrawTouchEligibilityRejectsColorCollectionViewArea", testDrawTouchEligibilityRejectsColorCollectionViewArea),
        ("testDrawTouchEligibilityRejectsEditToolCollectionViewArea", testDrawTouchEligibilityRejectsEditToolCollectionViewArea),
        ("testDrawGestureIsAvailableAfterZoomEnds", testDrawGestureIsAvailableAfterZoomEnds),
        ("testSingleFingerDrawingHasPriorityOverScrollPanAfterZoom", testSingleFingerDrawingHasPriorityOverScrollPanAfterZoom),
        ("testDrawGestureIsBlockedWhilePinching", testDrawGestureIsBlockedWhilePinching),
        ("testDrawTouchCollectorOnlyFinishesWhenTheTrackedTouchEnds", testDrawTouchCollectorOnlyFinishesWhenTheTrackedTouchEnds),
        ("testDrawTouchCollectorCancelsTrackingWhenAnotherTouchBegins", testDrawTouchCollectorCancelsTrackingWhenAnotherTouchBegins),
        ("testDrawTouchCollectorRejectsMultiTouchWhenNoTouchIsTracked", testDrawTouchCollectorRejectsMultiTouchWhenNoTouchIsTracked),
        ("testDrawLineWidthDoesNotChangeWithImageZoomScale", testDrawLineWidthDoesNotChangeWithImageZoomScale),
        ("testCanvasPreviewShowsTheInitialDotBeforeAStrokeMoves", testCanvasPreviewShowsTheInitialDotBeforeAStrokeMoves),
        ("testCanvasCanDiscardAnActivePreviewWithoutCommittingIt", testCanvasCanDiscardAnActivePreviewWithoutCommittingIt),
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

private final class LocatedTapGestureRecognizer: UITapGestureRecognizer {
    var testLocation: CGPoint = .zero

    override func location(in view: UIView?) -> CGPoint {
        testLocation
    }
}

private final class LocatedPanGestureRecognizer: UIPanGestureRecognizer {
    var testLocation: CGPoint = .zero

    override func location(in view: UIView?) -> CGPoint {
        testLocation
    }
}

private final class LocatedTouch: UITouch {
    private weak var referenceView: UIView?
    var testLocation: CGPoint = .zero

    init(referenceView: UIView) {
        self.referenceView = referenceView
        super.init()
    }

    override func location(in view: UIView?) -> CGPoint {
        guard let view else { return testLocation }
        return view.convert(testLocation, from: referenceView)
    }
}
