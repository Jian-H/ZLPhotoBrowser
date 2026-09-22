//
//  ZLPaths.swift
//  ZLPhotoBrowser
//
//  Created by long on 2023/9/25.
//
//  Copyright (c) 2020 Long Zhang <495181165@qq.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import UIKit

// MARK: 涂鸦path

public class ZLDrawPath: NSObject {
    private static var pathIndex = 0
    
    private let pathColor: UIColor
    
    private let pathWidth: CGFloat
    
    private let defaultLinePath: CGFloat
    
    private var bgPath: UIBezierPath
    
    private let ratio: CGFloat
    
    /// 归一化坐标点（已除以 ratio）。每一个有效触点都是路径节点，不能
    /// 因为渲染平滑而被向后移动或删除。
    private var points: [CGPoint] = []
    
    /// 命中测试用的描边 CGPath 缓存，key 为 strokeWidth，path 变化时清空
    private var strokedPathCache: (strokeWidth: CGFloat, path: CGPath)?
    
    // Coalesced touch samples can contain the same coordinate more than once.
    // Only coalesce numerically identical points; a distance threshold here
    // causes short handwriting strokes to disappear.
    private let duplicatePointTolerance: CGFloat = 0.001
    
    let index: Int
    
    var path: UIBezierPath

    var strokeColor: UIColor { pathColor }

    var renderBounds: CGRect {
        let radius = max(path.lineWidth, bgPath.lineWidth) / 2
        return path.cgPath.boundingBoxOfPath.insetBy(dx: -radius, dy: -radius)
    }

    var renderPadding: CGFloat {
        max(path.lineWidth, bgPath.lineWidth) / 2 + 2
    }

    var sampledPointCount: Int { points.count }
    
    var willDelete = false
    
    init(pathColor: UIColor, pathWidth: CGFloat, defaultLinePath: CGFloat, ratio: CGFloat, startPoint: CGPoint) {
        self.pathColor = pathColor
        self.pathWidth = pathWidth
        self.defaultLinePath = defaultLinePath
        self.ratio = ratio
        
        path = UIBezierPath()
        path.lineWidth = pathWidth / ratio
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        
        bgPath = UIBezierPath()
        bgPath.lineWidth = pathWidth / ratio + defaultLinePath
        bgPath.lineCapStyle = .round
        bgPath.lineJoinStyle = .round
        
        let normalized = CGPoint(x: startPoint.x / ratio, y: startPoint.y / ratio)
        points.append(normalized)
        path.move(to: normalized)
        bgPath.move(to: normalized)
        
        index = Self.pathIndex
        Self.pathIndex += 1
        
        super.init()
    }
    
    func addLine(to point: CGPoint) {
        let normalized = CGPoint(x: point.x / ratio, y: point.y / ratio)
        appendLineIfNeeded(normalized)
    }

    func addLines(_ points: ArraySlice<CGPoint>) {
        for point in points {
            let normalized = CGPoint(x: point.x / ratio, y: point.y / ratio)
            appendLineIfNeeded(normalized)
        }
    }

    func previewPath(adding points: [CGPoint]) -> UIBezierPath {
        guard !points.isEmpty else { return path }
        guard let preview = path.copy() as? UIBezierPath else { return path }
        var last = self.points[self.points.count - 1]
        for point in points {
            let normalized = CGPoint(x: point.x / ratio, y: point.y / ratio)
            if Self.distance(last, normalized) > duplicatePointTolerance {
                preview.addLine(to: normalized)
                last = normalized
            }
        }
        return preview
    }
    
    /// 保留 API 语义。路径已随每个原始触点增量追加，收笔时无需重建。
    func finishDrawing() {
        strokedPathCache = nil
    }
    
    /// 判断某个点是否命中当前笔画（用于橡皮擦）。
    /// 原生 `UIBezierPath.contains` 判定的是填充区域，对于开放的描边路径命中率很差。
    /// 这里先用 `copy(strokingWithWidth:)` 将路径按线宽+额外半径膨胀成实际可见区域，再做命中判断。
    /// - Parameters:
    ///   - point: 命中测试点（与 `path` 同坐标系）
    ///   - extraRadius: 额外容差半径（例如橡皮擦半径）
    func hitTest(_ point: CGPoint, extraRadius: CGFloat) -> Bool {
        let stroked = strokedPath(for: extraRadius)
        return stroked.contains(point)
    }
    
    /// 判断一条线段（上一个橡皮擦点 → 当前橡皮擦点）是否命中该笔画。
    /// 用于快速滑动时避免跳过细长笔画。
    func hitTest(from start: CGPoint, to end: CGPoint, extraRadius: CGFloat) -> Bool {
        let stroked = strokedPath(for: extraRadius)
        if stroked.contains(end) { return true }
        if stroked.contains(start) { return true }
        
        // 线段均匀采样
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        // 采样步长取橡皮擦半径的一半，保证不会在两个采样点间漏掉
        let step = max(extraRadius * 0.5, 1)
        let sampleCount = Int(distance / step)
        guard sampleCount > 0 else { return false }
        
        for i in 1..<sampleCount {
            let t = CGFloat(i) / CGFloat(sampleCount)
            let p = CGPoint(x: start.x + dx * t, y: start.y + dy * t)
            if stroked.contains(p) { return true }
        }
        return false
    }
    
    /// 获取/生成描边膨胀后的 CGPath。笔画结束后 path 不再变化，缓存可长期复用。
    private func strokedPath(for extraRadius: CGFloat) -> CGPath {
        let strokeWidth = max(path.lineWidth + extraRadius * 2, 1)
        if let cache = strokedPathCache, abs(cache.strokeWidth - strokeWidth) < 0.01 {
            return cache.path
        }
        let stroked = path.cgPath.copy(
            strokingWithWidth: strokeWidth,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 0
        )
        strokedPathCache = (strokeWidth, stroked)
        return stroked
    }
    
    private func appendLineIfNeeded(_ point: CGPoint) {
        guard let last = points.last else {
            points.append(point)
            return
        }
        let d = Self.distance(last, point)
        if d <= duplicatePointTolerance {
            return
        }
        points.append(point)
        path.addLine(to: point)
        bgPath.addLine(to: point)
        strokedPathCache = nil
    }
    
    private static func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        hypot(p2.x - p1.x, p2.y - p1.y)
    }
    
    func drawPath() {
        let isDot = points.count == 1
        let point = points.first

        if willDelete {
            UIColor.white.set()
            if isDot, let point {
                UIBezierPath(
                    arcCenter: point,
                    radius: bgPath.lineWidth / 2,
                    startAngle: 0,
                    endAngle: .pi * 2,
                    clockwise: true
                ).fill()
            } else {
                bgPath.stroke()
            }
            pathColor.withAlphaComponent(0.7).set()
        } else {
            pathColor.set()
        }
        
        if isDot, let point {
            UIBezierPath(
                arcCenter: point,
                radius: path.lineWidth / 2,
                startAngle: 0,
                endAngle: .pi * 2,
                clockwise: true
            ).fill()
        } else {
            path.stroke()
        }
    }
}

public extension ZLDrawPath {
    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? ZLDrawPath else {
            return false
        }
        
        return index == object.index
    }
}

// MARK: 马赛克path

public class ZLMosaicPath: NSObject {
    let path: UIBezierPath
    
    let ratio: CGFloat
    
    let startPoint: CGPoint
    
    var linePoints: [CGPoint] = []
    
    init(pathWidth: CGFloat, ratio: CGFloat, startPoint: CGPoint) {
        path = UIBezierPath()
        path.lineWidth = pathWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: startPoint)
        
        self.ratio = ratio
        self.startPoint = CGPoint(x: startPoint.x / ratio, y: startPoint.y / ratio)
        
        super.init()
    }
    
    func addLine(to point: CGPoint) {
        path.addLine(to: point)
        linePoints.append(CGPoint(x: point.x / ratio, y: point.y / ratio))
    }
}
