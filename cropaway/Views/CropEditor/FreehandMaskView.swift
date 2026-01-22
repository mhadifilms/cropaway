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
    let hitRadius: CGFloat = 12
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
            let path = Path { p in
                p.move(to: vertices[0].position.denormalized(to: videoSize))
                for v in vertices.dropFirst() {
                    p.addLine(to: v.position.denormalized(to: videoSize))
                }
                p.closeSubpath()
            }
            if path.contains(point) {
                return .insideShape
            }
        }

        return .background
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

    // UI constants
    private let vertexSize: CGFloat = 12
    private let handleSize: CGFloat = 8
    private let closeThreshold: CGFloat = 20

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
                .allowsHitTesting(false)

                // Invisible gesture layer
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(tapGesture)
                    .gesture(dragGesture)

                // Add curve button (outside canvas)
                if let selectedIdx = selectedVertexIndex,
                   selectedIdx < vertices.count,
                   vertices[selectedIdx].controlOut == nil {
                    addCurveButton(for: selectedIdx)
                }

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

    // MARK: - Gestures

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                handleTap(at: value.location)
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if case .idle = interactionState {
                    startDrag(at: value.startLocation)
                }
                continueDrag(to: value.location, from: value.startLocation)
            }
            .onEnded { _ in
                endDrag()
            }
    }

    // MARK: - Tap Handling

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
                closeShape()
            } else {
                selectedVertexIndex = selectedVertexIndex == i ? nil : i
            }

        case .handleIn(let i), .handleOut(let i):
            selectedVertexIndex = i

        case .insideShape:
            selectedVertexIndex = nil

        case .background:
            if selectedVertexIndex != nil {
                selectedVertexIndex = nil
            } else if !isShapeClosed {
                addVertex(at: point)
            }
        }
    }

    private func addVertex(at point: CGPoint) {
        let normalized = point.normalized(to: videoSize).clamped()

        // Check if near first vertex to close
        if vertices.count >= 3 {
            let firstPos = vertices[0].position.denormalized(to: videoSize)
            if point.distance(to: firstPos) < closeThreshold {
                closeShape()
                return
            }
        }

        vertices.append(MaskVertex(position: normalized))
        saveToPathData()
    }

    // MARK: - Drag Handling

    private func startDrag(at point: CGPoint) {
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
            selectedVertexIndex = i

        case .handleOut(let i):
            interactionState = .draggingHandleOut(
                index: i,
                startOffset: vertices[i].controlOut ?? .zero
            )
            selectedVertexIndex = i

        case .vertex(let i):
            interactionState = .draggingVertex(
                index: i,
                startPos: vertices[i].position
            )
            selectedVertexIndex = i

        case .insideShape where isShapeClosed:
            interactionState = .draggingShape(
                startPositions: vertices.map { $0.position }
            )

        case .background, .insideShape:
            break
        }
    }

    private func continueDrag(to point: CGPoint, from start: CGPoint) {
        let dx = (point.x - start.x) / videoSize.width
        let dy = (point.y - start.y) / videoSize.height

        switch interactionState {
        case .draggingVertex(let i, let startPos):
            guard i < vertices.count else { return }
            vertices[i].position = CGPoint(
                x: (startPos.x + dx).clamped(to: 0...1),
                y: (startPos.y + dy).clamped(to: 0...1)
            )

        case .draggingHandleIn(let i, let startOffset):
            guard i < vertices.count else { return }
            let newOffset = CGPoint(x: startOffset.x + dx, y: startOffset.y + dy)
            vertices[i].controlIn = newOffset
            if !NSEvent.modifierFlags.contains(.option) {
                vertices[i].controlOut = CGPoint(x: -newOffset.x, y: -newOffset.y)
            }

        case .draggingHandleOut(let i, let startOffset):
            guard i < vertices.count else { return }
            let newOffset = CGPoint(x: startOffset.x + dx, y: startOffset.y + dy)
            vertices[i].controlOut = newOffset
            if !NSEvent.modifierFlags.contains(.option) {
                vertices[i].controlIn = CGPoint(x: -newOffset.x, y: -newOffset.y)
            }

        case .draggingShape(let startPositions):
            for i in vertices.indices {
                guard i < startPositions.count else { continue }
                vertices[i].position = CGPoint(
                    x: (startPositions[i].x + dx).clamped(to: 0...1),
                    y: (startPositions[i].y + dy).clamped(to: 0...1)
                )
            }

        case .idle:
            break
        }
    }

    private func endDrag() {
        if case .idle = interactionState { return }
        interactionState = .idle
        saveToPathData()
        onEditEnded?()
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
        }

        // Draw shadow
        context.stroke(path, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: 4))
        // Draw main stroke
        context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 2))
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
                    x: pos.x - (vertexSize + 8) / 2,
                    y: pos.y - (vertexSize + 8) / 2,
                    width: vertexSize + 8,
                    height: vertexSize + 8
                )
                context.stroke(
                    Circle().path(in: outerRect),
                    with: .color(.green),
                    lineWidth: 2
                )
            }

            // Shadow
            let shadowRect = CGRect(
                x: pos.x - vertexSize / 2,
                y: pos.y - vertexSize / 2,
                width: vertexSize,
                height: vertexSize
            )
            context.fill(
                Circle().path(in: shadowRect.offsetBy(dx: 1, dy: 1)),
                with: .color(.black.opacity(0.3))
            )

            // Main vertex
            context.fill(
                Circle().path(in: shadowRect),
                with: .color(isSelected ? .accentColor : .white)
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
        context.stroke(line, with: .color(color.opacity(0.6)), lineWidth: 1)

        // Handle circle
        let rect = CGRect(
            x: handlePos.x - handleSize / 2,
            y: handlePos.y - handleSize / 2,
            width: handleSize,
            height: handleSize
        )
        context.fill(Circle().path(in: rect), with: .color(color))
    }

    // MARK: - UI Components

    @ViewBuilder
    private func addCurveButton(for index: Int) -> some View {
        let pos = vertices[index].position.denormalized(to: videoSize)

        Button {
            vertices[index].controlOut = CGPoint(x: 0.05, y: 0)
            vertices[index].controlIn = CGPoint(x: -0.05, y: 0)
            saveToPathData()
        } label: {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .padding(5)
                .background(Color.accentColor)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .position(x: pos.x + 24, y: pos.y - 24)
    }

    private var instructionsView: some View {
        VStack {
            Spacer()
            HStack {
                if !isShapeClosed {
                    if vertices.isEmpty {
                        Text("Click to place points")
                    } else if vertices.count < 3 {
                        Text("Add more points (\(vertices.count)/3 minimum)")
                    } else {
                        Text("Click first point to close shape")
                    }
                } else {
                    Text("Select vertex to edit curves \u{2022} Drag inside to move")
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
        saveToPathData()
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

// MARK: - Toolbar

struct FreehandToolbar: View {
    let hasPoints: Bool
    let onClear: () -> Void
    let onDeleteSelected: (() -> Void)?

    init(hasPoints: Bool, onClear: @escaping () -> Void, onDeleteSelected: (() -> Void)? = nil) {
        self.hasPoints = hasPoints
        self.onClear = onClear
        self.onDeleteSelected = onDeleteSelected
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "scribble.variable")
                .foregroundStyle(.secondary)

            Text(hasPoints ? "Click vertex to edit" : "Click to place points")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            if hasPoints {
                Button("Clear All") {
                    onClear()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Extensions

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    FreehandMaskView(
        points: .constant([
            CGPoint(x: 0.2, y: 0.2),
            CGPoint(x: 0.8, y: 0.3),
            CGPoint(x: 0.7, y: 0.8),
            CGPoint(x: 0.3, y: 0.7)
        ]),
        isDrawing: .constant(false),
        pathData: .constant(nil),
        videoSize: CGSize(width: 640, height: 360)
    )
    .frame(width: 640, height: 360)
    .background(Color.gray)
}
