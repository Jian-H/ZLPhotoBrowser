# Raw Touch Drawing Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drive every drawing stroke from raw UIKit touch samples so its first point and all valid short/fast movement are visible immediately and saved exactly once.

**Architecture:** `ZLDrawTouchCollector` remains the UIKit boundary and captures the eligible single touch through its full lifecycle. An internal `ZLDrawStrokeSession` in the same file will make actual and predicted point handling deterministic and unit-testable. `ZLEditImageViewController` will create, preview, and commit the same active `ZLDrawPath` from that session; `UIPanGestureRecognizer` will only control existing chrome and competing gestures.

**Tech Stack:** Swift 5, UIKit, Core Animation, XCTest, Swift Package Manager, Xcode simulator build.

**Spec:** `docs/superpowers/specs/2026-09-22-raw-touch-drawing-design.md`

## Global Constraints

- Preserve `ZLDrawPath`, `ZLEditImageModel.drawPaths`, `ZLEditorManager`, undo/redo, export, and all public APIs.
- Preserve single-touch drawing, sticker priority, scroll-view failure dependency, and toolbar hit testing.
- A tap remains a dot; predicted samples are preview-only and never persisted in `ZLDrawPath`.
- Add no dependencies and keep the source deployment floor at iOS 10.
- Build/test locally with `CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0`; do not edit project deployment settings.

---

### Task 1: Create a deterministic raw-stroke session

**Files:**
- Modify: `Tests/ZLPhotoBrowserTests/ZLPhotoBrowserTests.swift:4-50`
- Modify: `Sources/Edit/ZLDrawTouchCollector.swift:5-76`

**Interfaces:**
- Consumes: `CGPoint` samples converted by `ZLEditImageViewController` from `UITouch` values.
- Produces: internal `ZLDrawStrokeSession` with `init(actualPoints: [CGPoint])`, `append(actualPoints:predictedPoints:)`, `takeUnrenderedActualPoints() -> ArraySlice<CGPoint>`, `predictedPoints`, and `clearPredictedPoints()`.
- Later consumers: controller uses one session per eligible touch; tests use the session without constructing `UITouch`.

- [ ] **Step 1: Write the failing tests**

Add these methods before `static var allTests`:

```swift
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

func testDrawStrokeSessionReplaysAShortStrokeIntoItsPath() throws {
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
```

Append both methods to `allTests`.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodebuild test -workspace .swiftpm/xcode/package.xcworkspace -scheme ZLPhotoBrowser -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:ZLPhotoBrowserTests/ZLPhotoBrowserTests/testDrawStrokeSessionPreservesEveryActualPointAndSeparatesPredictions CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0
```

Expected: compilation fails with `cannot find 'ZLDrawStrokeSession' in scope`, proving the test is exercising the new unit rather than existing path behavior.

- [ ] **Step 3: Implement the minimal session**

Add the following internal type below `ZLDrawTouchCollector` in `Sources/Edit/ZLDrawTouchCollector.swift`:

```swift
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
        let points = actualPoints[nextUnrenderedActualPointIndex...]
        nextUnrenderedActualPointIndex = actualPoints.count
        return points
    }

    func clearPredictedPoints() {
        predictedPoints.removeAll(keepingCapacity: true)
    }
}
```

Keep the session internal, with no UIKit event ownership and no public API exposure.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run the Step 2 command with both session tests selected. Expected: both pass.

- [ ] **Step 5: Commit Task 1**

```bash
git add Sources/Edit/ZLDrawTouchCollector.swift Tests/ZLPhotoBrowserTests/ZLPhotoBrowserTests.swift
git commit -m "Add raw draw stroke session"
```

### Task 2: Make the raw-touch session own the active drawing path

**Files:**
- Modify: `Sources/Edit/ZLEditImageViewController.swift:245-257,1273-1309,1665-1743,1940-1946`

**Interfaces:**
- Consumes: `ZLDrawStrokeSession` from Task 1 and raw `UITouch` batches emitted by `ZLDrawTouchCollector`.
- Produces: one previewed `activeDrawPath` per touch, persisted once through `drawingImageView.commit(_:allPaths:)` and `editorManager.storeAction(.draw(_:))`.
- Preserves: existing `drawAction(_:)` tool routing, toolbar timing, and `shouldCollectDrawTouch(_:)` eligibility criteria.

- [ ] **Step 1: Replace Pan-owned path lifecycle with session-owned lifecycle**

In `ZLEditImageViewController`:

1. Replace `processedDrawSampleCount`, `rawDrawSamples`, `predictedDrawSamples`, `isCollectingRawDrawTouch`, `panHandledDrawTouch`, `pendingDrawFinishPoint`, and `initialDrawTouchPoint` with `private var drawStrokeSession: ZLDrawStrokeSession?` while retaining `activeDrawPath` and `suppressNextTapAction`.
2. In `beginRawDrawSamples`, map actual/predicted touches into `drawingImageView` coordinates, create `ZLDrawStrokeSession(actualPoints:)`, require its first unrendered point and `makeDrawPath(startPoint:)`, then immediately display the active path. Set `suppressNextTapAction = true` so a drawing touch cannot toggle the toolbar.
3. In `appendRawDrawSamples`, map samples to points, append to the session, take only unrendered actual points, append them to `activeDrawPath`, and update `drawingImageView.showPreview` with `path.previewPath(adding: session.predictedPoints)`.
4. In `finishRawDrawSamples`, append terminal samples first, then finish, append to `drawPaths`, commit to `drawingImageView`, store `.draw(path)`, clear the session and active path, and asynchronously clear `suppressNextTapAction`. Use this same finalization for a cancelled touch.
5. Reduce the `.draw` branch of `drawAction(_:)` to `setToolView(show: false)` on `.began` and `setToolView(show: true, delay: 0.5)` on `.ended/.cancelled`. Remove path construction, delayed finishing, and point fallbacks from Pan.
6. Remove the draw-specific `shouldReceive` capture of `initialDrawTouchPoint`; leave the delegate returning `true` and preserve all `gestureRecognizerShouldBegin` conditions.

- [ ] **Step 2: Run the full unit suite**

Run:

```bash
xcodebuild test -workspace .swiftpm/xcode/package.xcworkspace -scheme ZLPhotoBrowser -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0
```

Expected: all existing path/tile tests and both session tests pass with zero failures.

- [ ] **Step 3: Run the on-device input acceptance checks before committing**

UIKit does not allow constructing real `UITouch` values in XCTest, and this workspace's simulator cannot inject HID touch events. On a device, verify that a short stroke appears at `touchesBegan`, extends before lift-off, and is committed once when lifted; then verify a rapid long stroke has no initial gap. If either condition fails, do not commit and return to raw collector/session tracing.

- [ ] **Step 4: Commit Task 2**

```bash
git add Sources/Edit/ZLEditImageViewController.swift Tests/ZLPhotoBrowserTests/ZLPhotoBrowserTests.swift
git commit -m "Drive draw previews from raw touch samples"
```

### Task 3: Verify integration boundaries and document manual acceptance

**Files:**
- Modify: `Tests/ZLPhotoBrowserTests/ZLPhotoBrowserTests.swift:4-65` only if an integration-safe regression assertion is missing.
- Modify: no production files unless verification exposes a concrete failure.

**Interfaces:**
- Consumes: Task 2 raw-touch path lifecycle and the existing canvas tile renderer.
- Produces: build evidence and a repeatable manual acceptance checklist; no API or model changes.

- [ ] **Step 1: Run source and project integrity checks**

Run:

```bash
git diff --check
xcodebuild build -project ZLPhotoBrowser.xcodeproj -scheme ZLPhotoBrowser -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0
```

Expected: no whitespace errors and `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Run the full test suite**

Run:

```bash
xcodebuild test -workspace .swiftpm/xcode/package.xcworkspace -scheme ZLPhotoBrowser -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0
```

Expected: all tests pass with zero failures.

- [ ] **Step 3: Manually accept the real UIKit touch scenarios on a device**

Check, in this exact order:

1. With the toolbar visible, draw a very short fast stroke: its dot and movement are visible before lifting the finger.
2. Draw five rapid separate short strokes: each has its own start point and endpoint.
3. Draw a rapid connected stroke: no visible gap after the first sample.
4. Undo and redo the last stroke; confirm the exact stroke disappears and returns.
5. Use the eraser over a fast stroke, zoom, rotate/crop, then export; confirm the saved output matches the canvas.

- [ ] **Step 4: Commit any test-only verification adjustment, if one was necessary**

```bash
git add Tests/ZLPhotoBrowserTests/ZLPhotoBrowserTests.swift
git commit -m "Cover raw drawing input regressions"
```

Skip this commit if no test file changed in Task 3.

## Plan Self-Review

- Spec coverage: input ownership is Task 2; deterministic actual/predicted processing is Task 1; canvas commit/undo/export preservation is Task 2 plus Task 3; all required manual cases are Task 3.
- Placeholder scan: no unresolved implementation tasks, vague error handling, or undefined interfaces remain.
- Type consistency: the session names and signatures used by the controller and tests are defined in Task 1.
