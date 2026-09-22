import UIKit

/// Observes the unfiltered touch stream without participating in gesture
/// arbitration. The drawing pan recognizer remains responsible for deciding
/// whether the sequence is a drawing gesture.
final class ZLDrawTouchCollector: UIGestureRecognizer {
    typealias SamplesHandler = (_ actual: [UITouch], _ predicted: [UITouch]) -> Void

    var began: SamplesHandler?
    var moved: SamplesHandler?
    var ended: SamplesHandler?

    /// The collector is attached to the controller root view. Let its owner
    /// decide whether the current touch belongs to the drawable image area.
    var shouldCollect: ((UITouch) -> Bool)?

    /// Eligibility is deliberately captured on `touchesBegan`. Re-evaluating
    /// it on the terminal event loses a short stroke when another recognizer
    /// changes scroll or toolbar state between the two callbacks.
    private var collectedTouch: UITouch?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard collectedTouch == nil,
              let touch = touches.first(where: { shouldCollect?($0) ?? true }) else {
            super.touchesBegan(touches, with: event)
            return
        }
        collectedTouch = touch
        deliver(touch, event: event, handler: began)
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = collectedTouch, touches.contains(where: { $0 === touch }) {
            deliver(touch, event: event, handler: moved)
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = collectedTouch, touches.contains(where: { $0 === touch }) {
            deliver(touch, event: event, handler: ended)
            collectedTouch = nil
        }
        super.touchesEnded(touches, with: event)
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = collectedTouch, touches.contains(where: { $0 === touch }) {
            deliver(touch, event: event, handler: ended)
            collectedTouch = nil
        }
        super.touchesCancelled(touches, with: event)
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    private func deliver(_ touch: UITouch, event: UIEvent, handler: SamplesHandler?) {
        handler?(event.coalescedTouches(for: touch) ?? [touch], event.predictedTouches(for: touch) ?? [])
    }
}

/// Keeps one drawing touch's real and predicted samples independent from
/// UIKit gesture-recognizer state. Only real points are consumed into the
/// persisted ZLDrawPath; predicted points are intentionally preview-only.
final class ZLDrawStrokeSession {
    private var actualPoints: [CGPoint]
    private var nextUnrenderedActualPointIndex = 0

    private(set) var predictedPoints: [CGPoint] = []

    init(actualPoints: [CGPoint]) {
        self.actualPoints = actualPoints
    }

    func append(actualPoints: [CGPoint], predictedPoints: [CGPoint]) {
        for point in actualPoints where self.actualPoints.last != point {
            self.actualPoints.append(point)
        }
        self.predictedPoints = predictedPoints
    }

    func takeUnrenderedActualPoints() -> ArraySlice<CGPoint> {
        guard nextUnrenderedActualPointIndex < actualPoints.count else {
            return []
        }
        let points = actualPoints[nextUnrenderedActualPointIndex...]
        nextUnrenderedActualPointIndex = actualPoints.count
        return points
    }

    func clearPredictedPoints() {
        predictedPoints.removeAll(keepingCapacity: true)
    }
}
