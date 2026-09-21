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

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        deliver(touches, event: event, handler: began)
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        deliver(touches, event: event, handler: moved)
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        deliver(touches, event: event, handler: ended)
        super.touchesEnded(touches, with: event)
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        deliver(touches, event: event, handler: ended)
        super.touchesCancelled(touches, with: event)
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    private func deliver(_ touches: Set<UITouch>, event: UIEvent, handler: SamplesHandler?) {
        guard let touch = touches.first else { return }
        guard shouldCollect?(touch) ?? true else { return }
        handler?(event.coalescedTouches(for: touch) ?? [touch], event.predictedTouches(for: touch) ?? [])
    }
}
