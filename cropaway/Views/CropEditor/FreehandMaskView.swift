//
//  FreehandMaskView.swift
//  cropaway
//
//  NLE-style mask tool: click to place vertices, drag handles for bezier curves
//  Uses unified gesture pattern to avoid SwiftUI gesture conflicts

import SwiftUI

// MARK: - Hit Testing

struct MaskHitTester {
    let vertices: [MaskVertex]
    let videoSize: CGSize
    let hitRadius: CGFloat = 14
    let isShapeClosed: Bool
    let selectedVertexIndex: Int?

    enum HitResult: Equatable {
        case handleIn(Int)
        case handleOut(Int)
        case vertex(Int)
        case insideShape
        case background
    }

    func hitTest(_ point: CGPoint) -> HitResult {
        // Priority: bezier handles > vertices > shape interior > background
        // Check smallest targets first

        // 1. Check bezier handles (only for selected vertex)
        if let selectedIdx = selectedVertexIndex, selectedIdx < vertices.count {
            let v = vertices[selectedIdx]
            let pos = v.position.denormalized(to: videoSize)

            if let handleIn = v.controlIn {
                let handlePos = CGPoint(
                    x: pos.x + handleIn.x * videoSize.width,
                    y: pos.y + handleIn.y * videoSize.height
                )
                if point.distance(to: handlePos) < hitRadius {
                    return .handleIn(selectedIdx)
                }
            }

            if let handleOut = v.controlOut {
                let handlePos = CGPoint(
                    x: pos.x + handleOut.x * videoSize.width,
                    y: pos.y + handleOut.y * videoSize.height
                )
                if point.distance(to: handlePos) < hitRadius {
                    return .handleOut(selectedIdx)
                }
            }
        }

        // 2. Check all vertices
        for (i, v) in vertices.enumerated() {
            let pos = v.position.denormalized(to: videoSize)
            if point.distance(to: pos) < hitRadius {
                return .vertex(i)
            }
        }

        // 3. Check inside closed shape
        if isShapeClosed && vertices.count >= 3 {
            let path = buildShapePath()
            if path.contains(point) {
                return .insideShape
            }
        }

        return .background
    }

    private func buildShapePath() -> Path {
        Path { p in
            guard vertices.count >= 3 else { return }
            p.move(to: vertices[0].position.denormalized(to: videoSize))

            for i in 1..<vertices.count {
                let from = vertices[i-1]
                let to = vertices[i]
                addSegment(to: &p, from: from, to: to)
            }

            // Close path
            addSegment(to: &p, from: vertices.last!, to: vertices.first!)
            p.closeSubpath()
        }
    }

    private func addSegment(to path: inout Path, from: MaskVertex, to: MaskVertex) {
        let fromPx = from.position.denormalized(to: videoSize)
        let toPx = to.position.denormalized(to: videoSize)

        if let ctrlOut = from.controlOut, let ctrlIn = to.controlIn {
            let ctrl1 = CGPoint(
                x: fromPx.x + ctrlOut.x * videoSize.width,
                y: fromPx.y + ctrlOut.y * videoSize.height
            )
            let ctrl2 = CGPoint(
                x: toPx.x + ctrlIn.x * videoSize.width,
                y: toPx.y + ctrlIn.y * videoSize.height
            )
            path.addCurve(to: toPx, control1: ctrl1, control2: ctrl2)
        } else {
            path.addLine(to: toPx)
        }
    }
}

// MARK: - Interaction State Machine

enum MaskInteractionState: Equatable {
    case idle
    case draggingVertex(index: Int, startPos: CGPoint)
    case draggingHandleIn(index: Int, startOffset: CGPoint)
    case draggingHandleOut(index: Int, startOffset: CGPoint)
    case draggingShape(startPositions: [CGPoint])
}

// MARK: - Main View

struct FreehandMaskView: View {
    @Binding var points: [CGPoint]
    @Binding var isDrawing: Bool
    @Binding var pathData: Data?
    let videoSize: CGSize
    var onEditEnded: (() -> Void)? = nil

    // Internal state
    @State private var vertices: [MaskVertex] = []
    @State private var selectedVertexIndex: Int? = nil
    @State private var isShapeClosed: Bool = false
    @State private var interactionState: MaskInteractionState = .idle
    @State private var dragStartLocation: CGPoint = .zero
    @State private var renderTrigger: Int = 0  // Force canvas redraw
    @State private var isCreatingNewVertex: Bool = false  // Track if we're dragging out handles for a new vertex
    @State private var newVertexIndex: Int? = nil  // Index of vertex being created

    // UI constants
    private let vertexSize: CGFloat = 14
    private let handleSize: CGFloat = 10
    private let closeThreshold: CGFloat = 20
    private let tapThreshold: CGFloat = 5  // Max movement to count as tap

    // Initializers
    init(points: Binding<[CGPoint]>, isDrawing: Binding<Bool>, pathData: Binding<Data?>, videoSize: CGSize, onEditEnded: (() -> Void)? = nil) {
        self._points = points
        self._isDrawing = isDrawing
        self._pathData = pathData
        self.videoSize = videoSize
        self.onEditEnded = onEditEnded
    }

    init(points: Binding<[CGPoint]>, isDrawing: Binding<Bool>, videoSize: CGSize, onEditEnded: (() -> Void)? = nil) {
        self._points = points
        self._isDrawing = isDrawing
        self._pathData = .constant(nil)
        self.videoSize = videoSize
        self.onEditEnded = onEditEnded
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Canvas for rendering (no hit testing)
                Canvas { context, size in
                    drawPath(context: context)
                    drawVertices(context: context)
                    drawBezierHandles(context: context)
                }
                .id(renderTrigger)  // Force redraw when state changes
                .allowsHitTesting(false)

                // Unified gesture layer - single gesture handles both tap and drag
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(unifiedGesture)

                // Instructions overlay
                instructionsView
            }
            .onAppear { loadFromPathData() }
            .onChange(of: pathData) { _, _ in
                if case .idle = interactionState {
                    loadFromPathData()
                }
            }
        }
    }

    // MARK: - Unified Gesture (handles both tap and drag)

    private var unifiedGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartLocation == .zero {
                    // First event - store start location and determine action
                    dragStartLocation = value.startLocation
                    startInteraction(at: value.startLocation)
                }

                // Only process as drag if moved beyond tap threshold
                let distance = value.startLocation.distance(to: value.location)
                if distance > tapThreshold {
                    if isCreatingNewVertex, let idx = newVertexIndex {
                        // Dragging out bezier handles for new vertex
                        updateNewVertexHandles(at: idx, dragTo: value.location, from: value.startLocation)
                    } else {
                        continueDrag(to: value.location, from: value.startLocation)
                    }
                }
            }
            .onEnded { value in
                let distance = value.startLocation.distance(to: value.location)

                if distance <= tapThreshold && !isCreatingNewVertex {
                    // It was a tap, not a drag
                    handleTap(at: value.startLocation)
                } else {
                    // It was a drag - finalize
                    endDrag()
                }

                dragStartLocation = .zero
                interactionState = .idle
                isCreatingNewVertex = false
                newVertexIndex = nil
            }
    }

    // MARK: - Interaction Handling

    private func startInteraction(at point: CGPoint) {
        let hitTester = MaskHitTester(
            vertices: vertices,
            videoSize: videoSize,
            isShapeClosed: isShapeClosed,
            selectedVertexIndex: selectedVertexIndex
        )

        switch hitTester.hitTest(point) {
        case .handleIn(let i):
            interactionState = .draggingHandleIn(
                index: i,
                startOffset: vertices[i].controlIn ?? .zero
            )

        case .handleOut(let i):
            interactionState = .draggingHandleOut(
                index: i,
                startOffset: vertices[i].controlOut ?? .zero
            )

        case .vertex(let i):
            // Check if clicking first vertex to close
            if !isShapeClosed && i == 0 && vertices.count >= 3 {
                // Will be handled in tap - don't start drag
                interactionState = .idle
            } else {
                interactionState = .draggingVertex(
                    index: i,
                    startPos: vertices[i].position
                )
            }

        case .insideShape where isShapeClosed:
            interactionState = .draggingShape(
                startPositions: vertices.map { $0.position }
            )

        case .background where !isShapeClosed:
            // Create new vertex immediately - drag will add bezier handles
            let rawNormalized = point.normalized(to: videoSize)
            let normalized = CGPoint(x: max(0, min(1, rawNormalized.x)), y: max(0, min(1, rawNormalized.y)))

            // Check if near first vertex to close
            if vertices.count >= 3 {
                let firstPos = vertices[0].position.denormalized(to: videoSize)
                if point.distance(to: firstPos) < closeThreshold {
                    // Will close on tap/drag end
                    interactionState = .idle
                    return
                }
            }

            vertices.append(MaskVertex(position: normalized))
            newVertexIndex = vertices.count - 1
            isCreatingNewVertex = true
            selectedVertexIndex = newVertexIndex
            triggerRedraw()

        case .background, .insideShape:
            interactionState = .idle
        }
    }

    private func updateNewVertexHandles(at index: Int, dragTo point: CGPoint, from start: CGPoint) {
        guard index < vertices.count else { return }

        // Calculate handle offset based on drag distance and direction
        let dx = (point.x - start.x) / videoSize.width
        let dy = (point.y - start.y) / videoSize.height

        // The drag direction determines the "out" handle, opposite is "in" handle
        vertices[index].controlOut = CGPoint(x: dx, y: dy)
        vertices[index].controlIn = CGPoint(x: -dx, y: -dy)

        triggerRedraw()
    }

    private func handleTap(at point: CGPoint) {
        let hitTester = MaskHitTester(
            vertices: vertices,
            videoSize: videoSize,
            isShapeClosed: isShapeClosed,
            selectedVertexIndex: selectedVertexIndex
        )

        switch hitTester.hitTest(point) {
        case .vertex(let i):
            if !isShapeClosed && i == 0 && vertices.count >= 3 {
                // Clicking first vertex closes the shape
                closeShape()
                onEditEnded?()
            } else {
                // Toggle selection
                selectedVertexIndex = selectedVertexIndex == i ? nil : i
                triggerRedraw()
            }

        case .handleIn(let i), .handleOut(let i):
            selectedVertexIndex = i
            triggerRedraw()

        case .insideShape:
            selectedVertexIndex = nil
            triggerRedraw()

        case .background:
            if !isShapeClosed {
                // Check if near first vertex to close
                if vertices.count >= 3 {
                    let firstPos = vertices[0].position.denormalized(to: videoSize)
                    if point.distance(to: firstPos) < closeThreshold {
                        closeShape()
                        onEditEnded?()
                        return
                    }
                }

                // Add new vertex (simple click = no bezier handles)
                let rawNormalized = point.normalized(to: videoSize)
                let normalized = CGPoint(x: max(0, min(1, rawNormalized.x)), y: max(0, min(1, rawNormalized.y)))
                vertices.append(MaskVertex(position: normalized))
                selectedVertexIndex = vertices.count - 1
                saveToPathData()
                triggerRedraw()
                onEditEnded?()
            } else {
                selectedVertexIndex = nil
                triggerRedraw()
            }
        }
    }

    // MARK: - Drag Handling

    private func continueDrag(to point: CGPoint, from start: CGPoint) {
        let dx = (point.x - start.x) / videoSize.width
        let dy = (point.y - start.y) / videoSize.height

        switch interactionState {
        case .draggingVertex(let i, let startPos):
            guard i < vertices.count else { return }
            vertices[i].position = CGPoint(
                x: max(0, min(1, startPos.x + dx)),
                y: max(0, min(1, startPos.y + dy))
            )
            triggerRedraw()

        case .draggingHandleIn(let i, let startOffset):
            guard i < vertices.count else { return }
            let newOffset = CGPoint(x: startOffset.x + dx, y: startOffset.y + dy)
            vertices[i].controlIn = newOffset
            // Mirror to other handle unless Option is held
            if !NSEvent.modifierFlags.contains(.option) {
                vertices[i].controlOut = CGPoint(x: -newOffset.x, y: -newOffset.y)
            }
            triggerRedraw()

        case .draggingHandleOut(let i, let startOffset):
            guard i < vertices.count else { return }
            let newOffset = CGPoint(x: startOffset.x + dx, y: startOffset.y + dy)
            vertices[i].controlOut = newOffset
            // Mirror to other handle unless Option is held
            if !NSEvent.modifierFlags.contains(.option) {
                vertices[i].controlIn = CGPoint(x: -newOffset.x, y: -newOffset.y)
            }
            triggerRedraw()

        case .draggingShape(let startPositions):
            for i in vertices.indices {
                guard i < startPositions.count else { continue }
                vertices[i].position = CGPoint(
                    x: max(0, min(1, startPositions[i].x + dx)),
                    y: max(0, min(1, startPositions[i].y + dy))
                )
            }
            triggerRedraw()

        case .idle:
            break
        }
    }

    private func endDrag() {
        if case .idle = interactionState { return }
        saveToPathData()
        onEditEnded?()
    }

    private func triggerRedraw() {
        renderTrigger += 1
    }

    // MARK: - Canvas Drawing

    private func drawPath(context: GraphicsContext) {
        guard vertices.count >= 2 else { return }

        var path = Path()
        path.move(to: vertices[0].position.denormalized(to: videoSize))

        for i in 1..<vertices.count {
            addCurveSegment(to: &path, from: vertices[i-1], to: vertices[i])
        }

        if isShapeClosed && vertices.count >= 3 {
            addCurveSegment(to: &path, from: vertices.last!, to: vertices.first!)
            path.closeSubpath()
        }

        // Draw shadow
        context.stroke(path, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        // Draw main stroke
        context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    private func addCurveSegment(to path: inout Path, from: MaskVertex, to: MaskVertex) {
        let fromPx = from.position.denormalized(to: videoSize)
        let toPx = to.position.denormalized(to: videoSize)

        let hasFromHandle = from.controlOut != nil
        let hasToHandle = to.controlIn != nil

        if hasFromHandle && hasToHandle {
            let ctrl1 = CGPoint(
                x: fromPx.x + from.controlOut!.x * videoSize.width,
                y: fromPx.y + from.controlOut!.y * videoSize.height
            )
            let ctrl2 = CGPoint(
                x: toPx.x + to.controlIn!.x * videoSize.width,
                y: toPx.y + to.controlIn!.y * videoSize.height
            )
            path.addCurve(to: toPx, control1: ctrl1, control2: ctrl2)
        } else if hasFromHandle {
            let ctrl = CGPoint(
                x: fromPx.x + from.controlOut!.x * videoSize.width,
                y: fromPx.y + from.controlOut!.y * videoSize.height
            )
            path.addQuadCurve(to: toPx, control: ctrl)
        } else if hasToHandle {
            let ctrl = CGPoint(
                x: toPx.x + to.controlIn!.x * videoSize.width,
                y: toPx.y + to.controlIn!.y * videoSize.height
            )
            path.addQuadCurve(to: toPx, control: ctrl)
        } else {
            path.addLine(to: toPx)
        }
    }

    private func drawVertices(context: GraphicsContext) {
        for (i, v) in vertices.enumerated() {
            let pos = v.position.denormalized(to: videoSize)
            let isSelected = selectedVertexIndex == i
            let isFirstOpen = !isShapeClosed && i == 0 && vertices.count >= 3

            // Close indicator ring for first vertex
            if isFirstOpen {
                let outerRect = CGRect(
                    x: pos.x - (vertexSize + 10) / 2,
                    y: pos.y - (vertexSize + 10) / 2,
                    width: vertexSize + 10,
                    height: vertexSize + 10
                )
                context.stroke(
                    Circle().path(in: outerRect),
                    with: .color(.green),
                    lineWidth: 2
                )
            }

            // Shadow
            let shadowRect = CGRect(
                x: pos.x - vertexSize / 2 + 1,
                y: pos.y - vertexSize / 2 + 1,
                width: vertexSize,
                height: vertexSize
            )
            context.fill(
                Circle().path(in: shadowRect),
                with: .color(.black.opacity(0.3))
            )

            // Main vertex
            let mainRect = CGRect(
                x: pos.x - vertexSize / 2,
                y: pos.y - vertexSize / 2,
                width: vertexSize,
                height: vertexSize
            )
            context.fill(
                Circle().path(in: mainRect),
                with: .color(isSelected ? .accentColor : .white)
            )

            // Border for better visibility
            context.stroke(
                Circle().path(in: mainRect),
                with: .color(isSelected ? .white : .black.opacity(0.3)),
                lineWidth: 1
            )
        }
    }

    private func drawBezierHandles(context: GraphicsContext) {
        guard let i = selectedVertexIndex, i < vertices.count else { return }

        let v = vertices[i]
        let pos = v.position.denormalized(to: videoSize)

        // Control Out handle (blue/accent)
        if let handleOut = v.controlOut {
            drawHandle(
                context: context,
                origin: pos,
                offset: handleOut,
                color: .accentColor
            )
        }

        // Control In handle (orange)
        if let handleIn = v.controlIn {
            drawHandle(
                context: context,
                origin: pos,
                offset: handleIn,
                color: .orange
            )
        }
    }

    private func drawHandle(context: GraphicsContext, origin: CGPoint, offset: CGPoint, color: Color) {
        let handlePos = CGPoint(
            x: origin.x + offset.x * videoSize.width,
            y: origin.y + offset.y * videoSize.height
        )

        // Line from vertex to handle
        var line = Path()
        line.move(to: origin)
        line.addLine(to: handlePos)
        context.stroke(line, with: .color(color.opacity(0.7)), lineWidth: 1.5)

        // Handle circle shadow
        let shadowRect = CGRect(
            x: handlePos.x - handleSize / 2 + 1,
            y: handlePos.y - handleSize / 2 + 1,
            width: handleSize,
            height: handleSize
        )
        context.fill(Circle().path(in: shadowRect), with: .color(.black.opacity(0.3)))

        // Handle circle
        let rect = CGRect(
            x: handlePos.x - handleSize / 2,
            y: handlePos.y - handleSize / 2,
            width: handleSize,
            height: handleSize
        )
        context.fill(Circle().path(in: rect), with: .color(color))
        context.stroke(Circle().path(in: rect), with: .color(.white), lineWidth: 1)
    }

    // MARK: - UI Components

    private var instructionsView: some View {
        VStack {
            Spacer()
            HStack {
                if !isShapeClosed {
                    if vertices.isEmpty {
                        Text("Click to add point \u{2022} Click+drag for curves")
                    } else if vertices.count < 3 {
                        Text("Add more points (\(vertices.count)/3 min) \u{2022} Drag for curves")
                    } else {
                        Text("Click green point to close \u{2022} Drag for curves")
                    }
                } else {
                    Text("Drag vertex to move \u{2022} Drag handles for curves \u{2022} Drag inside to move all")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.bottom, 8)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Shape Management

    private func closeShape() {
        guard vertices.count >= 3 else { return }
        isShapeClosed = true
        isDrawing = false
        selectedVertexIndex = nil
        saveToPathData()
        triggerRedraw()
    }

    // MARK: - Persistence

    private func loadFromPathData() {
        if let data = pathData,
           let loadedVertices = try? JSONDecoder().decode([MaskVertex].self, from: data),
           !loadedVertices.isEmpty {
            vertices = loadedVertices
            isShapeClosed = loadedVertices.count >= 3
        } else if points.count >= 3 {
            vertices = points.map { MaskVertex(position: $0) }
            isShapeClosed = true
        } else if !points.isEmpty {
            vertices = points.map { MaskVertex(position: $0) }
            isShapeClosed = false
        } else {
            vertices = []
            isShapeClosed = false
        }
        selectedVertexIndex = nil
        triggerRedraw()
    }

    private func saveToPathData() {
        // Save simple points for backward compatibility
        points = vertices.map { $0.position }

        // Save full vertex data with bezier handles
        if let data = try? JSONEncoder().encode(vertices) {
            pathData = data
        }
    }
}

#Preview {
    FreehandMaskView(
        points: .constant([]),
        isDrawing: .constant(true),
        pathData: .constant(nil),
        videoSize: CGSize(width: 640, height: 360)
    )
    .frame(width: 640, height: 360)
    .background(Color.gray)
}
