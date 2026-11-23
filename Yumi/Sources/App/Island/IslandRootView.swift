import SwiftUI

/// Top-level SwiftUI view rendered inside the transparent panel
/// (`IslandConst.panelWidth` × `IslandConst.panelHeight`, glued to the top of the screen).
/// The island is drawn at the top-center; everything else is transparent and click-through.
/// Note: drag-drop is handled at the AppKit level in IslandWindowController (FileDropNSView),
/// not in SwiftUI, to avoid interfering with SwiftUI hit-testing.
struct IslandRootView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var model = IslandModel.shared

    var body: some View {
        IslandScene(state: state, model: model)
            .frame(width: IslandConst.panelWidth, height: IslandConst.panelHeight, alignment: .top)
            // Filming mode: the whole island larger, drawn at that size and not stretched
            .transformEnvironment(\.displayScale) { $0 *= IslandStudio.scale }
            .scaleEffect(IslandStudio.scale, anchor: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
    }
}

// MARK: - The stage of the mock-up: the island, the second square, and Yumi above them

struct IslandScene: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: IslandModel
    @AppStorage(IslandPrefs.workHabitKey) private var workHabit = YumiWorkHabit.current().rawValue
    @AppStorage(MacVitalsMonitor.defaultsKey) private var macVitals = true
    @AppStorage(IslandAccent.defaultsKey) private var accentName = IslandAccent.yumi.rawValue
    /// Counts the openings, so that the content rises again each time the island opens.
    @State private var openings = 0

    var body: some View {
        let stage = model.stage(for: state.mode)
        // What is live decides how wide the folded island is
        let folded = FoldedContent(module: FoldedIsland.live(in: state.modules, shown: model.liveModuleID),
                                   hover: model.foldedHover && stage == .compact)
        let ear = folded.ear(notchWidth: model.layout.notchWidth)
        // What Yumi says on his own, and the room the folded island makes for it
        let remark = model.launchStage == nil ? model.remark(in: state) : nil
        let speak = remark.map { RemarkLine.size(for: $0, minimum: model.layout.notchWidth + IslandConst.compactExtra) }
        let layout: IslandLayout = {
            var layout = model.layout
            layout.compactEar = ear
            if let speak {
                layout.speakWidth = CGFloat(speak.width)
                layout.speakBand = CGFloat(speak.band)
            }
            return layout
        }()
        let approval = state.pendingApproval != nil
        let busy = IslandModel.isBusy(state.effectiveState)
        let resolved = IslandScreen.resolve(view: state.view, state: state.effectiveState, approvalPending: approval)
        // The agent's module shows the agent at work while it works
        let screen: IslandScreen = resolved == .module && busy
            && model.selectedModule(in: state.modules)?.id == IslandModel.agentModuleID ? .working : resolved
        // The open island is as wide as its tab or its view asks, never narrower than the notch allows
        let notchUnits = layout.hasNotch ? layout.notchWidth / IslandConst.openScale : 0
        let openUnits = IslandOpenLayer.widthKind(for: screen, category: model.category).width(notch: notchUnits)
        let accent = (IslandAccent(rawValue: accentName) ?? .yumi).color
        let border: Color? = stage == .open
            ? (screen == .alert ? IslandTheme.amber : accent.opacity(0.7))
            : nil
        let drop = layout.notchDelta / IslandConst.launchScale
        let size: CGSize = {
            var open = layout
            open.openWidth = openUnits * IslandConst.openScale
            return open.size(stage, openHeight: model.openHeight)
        }()
        let seat = layout.seat(stage)
        let situation = IslandModel.Situation(
            stage: stage,
            screen: stage == .open ? screen : IslandScreen.resolve(view: .overview, state: state.effectiveState, approvalPending: approval),
            moduleID: stage == .open && screen == .module ? model.selectedModule(in: state.modules)?.id : nil,
            workHabit: YumiWorkHabit(rawValue: workHabit) ?? .coffee,
            music: folded.musicPlaying,
            chatActs: state.chatLive?.activity != nil,
            busy: busy,
            remarkMood: remark?.mood,
            strain: macVitals ? state.macStrain : nil)
        let middle = IslandConst.panelWidth / 2
        let launching = model.launchStage != nil

        ZStack(alignment: .top) {
            Color.clear

            // 0. The bubble of the second activity, which leaves the folded island like a drop
            FoldedBubble(module: stage == .compact ? FoldedIsland.second(in: state.modules, after: folded.module?.id) : nil,
                         island: layout.size(.compact, openHeight: 0), middle: middle)
                .opacity(stage == .compact ? 1 : 0)
                .environment(\.islandLayerShown, stage == .compact)

            // 1. The island: a black shape that cuts what it contains (`overflow: hidden`)
            IslandBody(width: size.width, height: size.height, radius: layout.cornerRadius(stage), border: border) {
                ZStack(alignment: .topLeading) {
                    // The halo of the launch, or of the goodbye with its few words
                    IslandGreetingLayer(phase: model.greeting,
                                        center: model.leaving ? CGPoint(x: 150, y: 70 + drop) : CGPoint(x: 130, y: 86 + drop),
                                        size: model.leaving
                                            ? CGSize(width: IslandConst.byeWidth, height: IslandConst.byeHeight + drop)
                                            : CGSize(width: IslandConst.greetWidth, height: IslandConst.greetHeight + drop),
                                        words: model.leaving ? Voice.goodbye(name: state.userName) : nil)
                        .scaleEffect(IslandConst.launchScale, anchor: .topLeading)
                        .modifier(IslandLayer(on: launching))

                    IslandSparks(start: model.sparksStart,
                                 scale: IslandConst.launchScale,
                                 center: CGPoint(x: IslandConst.greetWidth * IslandConst.launchScale / 2 + layout.seat(.greet).x,
                                                 y: layout.seat(.greet).y))

                    IslandSpeakLayer(remark: stage == .speak ? remark : nil,
                                     size: speak ?? Speak.Size(width: Double(layout.speakWidth), band: Double(layout.speakBand), textWidth: 0, lines: 1),
                                     notchHeight: layout.notchHeight, model: model)
                        .modifier(IslandLayer(on: stage == .speak))

                    IslandOpenLayer(state: state, model: model, screen: screen, width: openUnits)
                        .id(openings)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            model.openHeight = min(max(height * IslandConst.openScale, layout.notchHeight),
                                                   IslandConst.openHeightMax * IslandConst.openScale)
                        }
                        .scaleEffect(IslandConst.openScale, anchor: .topLeading)
                        .modifier(IslandLayer(on: stage == .open))
                        .environment(\.islandLayerShown, stage == .open)
                }
            } edge: {
                // Laid out in the island's width of the instant, so that it stays against
                // its right edge while the island widens or narrows
                IslandCompactLayer(content: folded, ear: ear, height: layout.notchHeight)
                    .modifier(IslandLayer(on: stage == .compact))
                    .environment(\.islandLayerShown, stage == .compact)
            }
            .animation(model.snap ? nil : .islandSpring(), value: size)

            // 2. Yumi, above the island: he travels between seats, and what he does may
            //    spill over its sides and below it.
            IslandActor(state: state, x: middle + seat.x, y: seat.y, scale: seat.scale)
                .animation(model.snap ? nil : .islandSpring(), value: seat)
                .opacity(state.isDraggingBot ? 0 : seat.opacity)
                .animation(model.snap ? nil : .islandEase(0.25), value: seat.opacity)
                .allowsHitTesting(false)
                .onAppear { model.actorAppeared() }
        }
        .environment(\.islandAccent, accent)
        .onAppear { model.direct(from: nil, to: situation) }
        .onChange(of: openUnits, initial: true) { _, units in model.layout.openWidth = units * IslandConst.openScale }
        .onChange(of: folded.module?.id, initial: true) { _, id in model.liveModuleID = id }
        .onChange(of: ear, initial: true) { _, ear in model.layout.compactEar = ear }
        .onChange(of: folded.controls.count, initial: true) { _, count in model.foldedControls = count }
        .onChange(of: situation) { old, new in model.direct(from: old, to: new) }
        .onChange(of: remark?.id, initial: true) { _, _ in
            model.speaking = remark != nil
            model.remarkAppeared(remark)
        }
        .onChange(of: speak) { _, speak in
            guard let speak else { return }
            model.layout.speakWidth = CGFloat(speak.width)
            model.layout.speakBand = CGFloat(speak.band)
        }
        .onChange(of: state.effectiveState) { old, new in model.track(state: old, new) }
        .onChange(of: state.memory.count) { old, new in
            // He learnt something while talking: a wink, no words
            if new > old, stage == .open, screen == .talk { model.wink() }
        }
        .onChange(of: state.chatLive) { old, new in
            // The end of an answer that created or modified something
            if new == nil, let done = old?.done,
               LiveChat.celebrates(done: done.map { ($0.kind.rawValue, $0.succeeded) }) {
                model.pose(.celebrate)
            }
        }
        .onChange(of: state.focusTask?.steps.last) { _, step in model.track(step: step) }
        .onChange(of: stage) { _, new in
            if new == .open { openings += 1 }
        }
    }
}

/// `.layer`: the layers cross-fade, the one coming in a little after the one going out.
private struct IslandLayer: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .animation(on ? .islandEase(0.28).delay(0.16) : .islandEase(0.14), value: on)
            .allowsHitTesting(on)
    }
}

// MARK: - Island shape

/// Flush with the top of the screen, rounded at the bottom
/// (`border-radius: 0 0 r r`; a radius too large for the box is reduced, as CSS does).
struct IslandShape: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = max(0, min(radius, rect.width / 2, rect.height))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// The island at one size. It is rebuilt at every frame of a change, so its width and height
/// follow `--spring` (.55 s) while its corners follow their own ease (.4 s), as in
/// `transition: width .55s var(--spring), height .55s var(--spring), border-radius .4s ease`.
struct IslandBody<Content: View, Edge: View>: View, Animatable {
    var width: CGFloat
    var height: CGFloat
    let radius: CGFloat
    /// The thin outline of the open island, in its colour; nil while folded.
    var border: Color?
    /// Layers anchored to the top-left corner of the island, each with its own width.
    let content: Content
    /// A layer that takes the width the island has at this instant.
    let edge: Edge

    init(width: CGFloat, height: CGFloat, radius: CGFloat, border: Color? = nil,
         @ViewBuilder content: () -> Content, @ViewBuilder edge: () -> Edge) {
        self.width = width
        self.height = height
        self.radius = radius
        self.border = border
        self.content = content()
        self.edge = edge()
    }

    nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, height) }
        set { width = newValue.first; height = newValue.second }
    }

    var body: some View {
        IslandCorners(width: width, height: height, radius: radius, border: border, content: content, edge: edge)
            .animation(.islandEase(0.4), value: radius)
            .animation(.islandEase(0.4), value: border)
    }
}

private struct IslandCorners<Content: View, Edge: View>: View, Animatable {
    let width: CGFloat
    let height: CGFloat
    var radius: CGFloat
    let border: Color?
    let content: Content
    let edge: Edge

    nonisolated var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    var body: some View {
        let shape = IslandShape(radius: radius)
        ZStack(alignment: .topLeading) {
            shape.fill(.black)
            content
                .frame(width: max(0, width), height: max(0, height), alignment: .topLeading)
                .overlay(alignment: .topTrailing) { edge }
                .clipShape(shape)
            // `border: 1px solid; border-top: 0`: the outline runs down the sides and round the bottom
            IslandOutline(radius: radius)
                .stroke(border ?? .clear, lineWidth: 1)
                .opacity(border == nil ? 0 : 1)
                .allowsHitTesting(false)
        }
        .frame(width: max(0, width), height: max(0, height), alignment: .topLeading)
    }
}

/// The sides and the bottom of `IslandShape`, inset half a line so the stroke stays inside.
private struct IslandOutline: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: 0.5, dy: 0)
        let r = max(0, min(radius, rect.width / 2, rect.height)) - 0.5
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - 0.5 - r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - 0.5 - r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY - 0.5))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - 0.5 - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

// MARK: - Yumi's seat

/// The one character of the island (`#actor` in the mock-up). He is a `BotCanvasView`,
/// sized for his seat: the character derives the width of his rim from the size it is
/// drawn at. Moving to another seat rebuilds him at every frame, so he grows and shrinks
/// for real instead of being scaled.
struct IslandActor: View, Animatable {
    @ObservedObject var state: AppState
    var x: CGFloat
    var y: CGFloat
    var scale: CGFloat

    nonisolated var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(x, AnimatablePair(y, scale)) }
        set { x = newValue.first; y = newValue.second.first; scale = newValue.second.second }
    }

    var body: some View {
        let side = IslandSeat.frameSide(scale: max(0.01, scale))
        BotCanvasView(state: state)
            .frame(width: side, height: side)
            .position(x: x, y: y)
    }
}
