import SwiftUI
import CoreText
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import CoreText
import SwiftUI

/// Everything the renderer needs for one image. BotEngine fills it from the soft body and
/// from the eased face values.
struct YumiFrame {
    // Soft body
    var h: CGFloat = 1
    var w: CGFloat = 1
    var lean: CGFloat = 0
    var y: CGFloat = 0
    var air = false
    var faceShift = CGPoint.zero
    var faceScale = CGSize(width: 1, height: 1)
    var yaw: CGFloat = 0
    var pitch: CGFloat = 0

    // Face (eased values of a YumiFace; `look` is not used here)
    var face = YumiFace()
    var pupil = CGPoint.zero
    var eyesScale: CGFloat = 1
    var blink: CGFloat = 1

    // Light
    var rim: [YumiRGB] = YumiRimTone.calm.stops
    var rimWidth: CGFloat = 2.6
    /// How much of the rim is drawn, 0…1. It draws itself when the light comes on.
    var drawn: CGFloat = 1
    /// Opacity of everything that is light: glow, inner light, floor, shine, glint.
    var light: CGFloat = 1
    var glow: CGFloat = 0.85

    // Props
    var props: [YumiHabit: CGFloat] = [:]
    var habitTime: CGFloat = 0
    var emberRadius: CGFloat = 1.9
    var emberHot = false
    var sip: CGFloat = 0
    /// The bubble and the z of the sleep: they fade when the sleep goes deep.
    var sleepFx: CGFloat = 1

    // Pose extras: seconds since the arms or the sparks started, nil when they are not out
    var armTime: CGFloat?
    var sparkTime: CGFloat?

    var drops: [YumiBlob.Drop] = []
    var puffs: [YumiBlob.Puff] = []
    var time: CGFloat = 0

    /// The scene being played for an outside event, if any (Character/YumiScenes.swift).
    var scene: YumiSceneMoment?

    /// What he wears, chosen in the settings (Contracts/IslandLookTypes.swift).
    var costume: YumiCostume = .none

    /// The blurred light, already drawn for a shape close to this one (see YumiLight).
    /// nil: it is drawn again for this picture.
    var storedLight: YumiLight?
}

/// The blurred part of the light (floor, halo, light inside the outline), drawn once for a
/// body at rest and reused, stretched and sheared, while the shape stays close to it: blurring
/// is what costs the most, and under the blur a few units of lean or height do not show.
struct YumiLight {
    /// Floor and halo, behind the body.
    let behind: Image
    /// Light spilling inside the outline; the body clips it.
    let inner: Image
    /// The shape they were drawn for.
    let h: CGFloat
    let w: CGFloat
    let lean: CGFloat

    /// The lean moves the top of the outline and barely its base: a shear about the base
    /// carries the pictures from the lean they were drawn for to `lean`.
    func lean(to lean: CGFloat) -> CGAffineTransform {
        let k = (lean - self.lean) / (68 * h)
        return CGAffineTransform(a: 1, b: 0, c: -k, d: 1, tx: 76 * k, ty: 0)
    }

    /// The part of the mock-up's box the pictures cover: the widest body at rest, its halo and its blur.
    static let bounds = CGRect(x: -50, y: -32, width: 200, height: 136)

    /// Draws both pictures with the same code as the live path, so they are identical to it.
    /// `unit` is the size of one unit in points, `scale` the pixels per point of the screen.
    @MainActor
    static func render(h: CGFloat, w: CGFloat, lean: CGFloat, rim: [YumiRGB], rimWidth: CGFloat,
                       unit: CGFloat, scale: CGFloat) -> YumiLight? {
        var f = YumiFrame()
        f.h = h; f.w = w; f.lean = lean; f.rim = rim; f.rimWidth = rimWidth
        let body = YumiRenderer.bodyPath(h: h, w: w, lean: lean)
        func picture(_ draw: @escaping (GraphicsContext) -> Void) -> Image? {
            let canvas = Canvas { context, _ in
                var c = context
                c.scaleBy(x: unit, y: unit)
                c.translateBy(x: -bounds.minX, y: -bounds.minY)
                draw(c)
            }
            .frame(width: bounds.width * unit, height: bounds.height * unit)
            let renderer = ImageRenderer(content: canvas)
            renderer.scale = scale
            return renderer.cgImage.map { Image(decorative: $0, scale: scale) }
        }
        guard let behind = picture({ YumiRenderer.drawBehind(f, body: body, in: $0) }),
              let inner = picture({ YumiRenderer.drawInner(f, body: body, in: $0) }) else { return nil }
        return YumiLight(behind: behind, inner: inner, h: h, w: w, lean: lean)
    }
}

/// Draws Yumi as design/maquette/reference.html does, element for element, in the
/// 100 × 84 box of the mock-up (the body spans x 8…92 and y 8…76 at rest). The caller
/// scales and places that box; nothing here knows about points or the island.
enum YumiRenderer {

    static let blur: CGFloat = 3.2
    private static let ink = Color.black

    // MARK: Outline

    /// `bodyPath(h, w, L)` of the mock-up: h is the height, w the width, L the lean of the top.
    static func bodyPath(h: CGFloat, w: CGFloat, lean L: CGFloat) -> Path {
        let by: CGFloat = 76, ty = by - 68 * h, tx = 50 + L
        let sy = by - 14 * pow(h, 0.7), wb = 1 + (w - 1) * 0.55
        let lx = 50 - 42 * w + L * 0.12, rx = 50 + 42 * w + L * 0.12
        let cy = sy - 31 * h, my = sy + (by - sy) * 0.71
        var p = Path()
        p.move(to: CGPoint(x: lx, y: sy))
        p.addCurve(to: CGPoint(x: tx, y: ty), control1: CGPoint(x: lx, y: cy), control2: CGPoint(x: tx - 23 * w, y: ty))
        p.addCurve(to: CGPoint(x: rx, y: sy), control1: CGPoint(x: tx + 23 * w, y: ty), control2: CGPoint(x: rx, y: cy))
        p.addCurve(to: CGPoint(x: 50, y: by), control1: CGPoint(x: rx, y: my), control2: CGPoint(x: 50 + 32 * wb, y: by))
        p.addCurve(to: CGPoint(x: lx, y: sy), control1: CGPoint(x: 50 - 32 * wb, y: by), control2: CGPoint(x: lx, y: my))
        p.closeSubpath()
        return p
    }

    // MARK: Shadings and masks

    /// The rim gradient, left to right across `rect` (SVG objectBoundingBox units).
    private static func across(_ rect: CGRect, _ rim: [YumiRGB]) -> GraphicsContext.Shading {
        .linearGradient(Gradient(stops: [.init(color: rim[0].color, location: 0),
                                         .init(color: rim[1].color, location: 0.5),
                                         .init(color: rim[2].color, location: 1)]),
                        startPoint: CGPoint(x: rect.minX, y: rect.midY), endPoint: CGPoint(x: rect.maxX, y: rect.midY))
    }

    private static let maskRect = Path(CGRect(x: -120, y: -120, width: 340, height: 320))

    /// Fades the top of the rim and of the glow: the light is stronger at the base and on the sides.
    private static func fadeTop(_ mask: inout GraphicsContext) {
        mask.fill(maskRect, with: .linearGradient(
            Gradient(stops: [.init(color: .white.opacity(0.28), location: 0), .init(color: .white, location: 0.55)]),
            startPoint: CGPoint(x: 0, y: -10), endPoint: CGPoint(x: 0, y: 100)))
    }

    /// Keeps the inner light to the lower part of the body.
    private static func lowerHalf(_ mask: inout GraphicsContext) {
        mask.fill(maskRect, with: .linearGradient(
            Gradient(stops: [.init(color: .white.opacity(0), location: 0), .init(color: .white, location: 1)]),
            startPoint: CGPoint(x: 0, y: 20), endPoint: CGPoint(x: 0, y: 80)))
    }

    static func line(_ a: CGPoint, _ b: CGPoint) -> Path {
        var p = Path(); p.move(to: a); p.addLine(to: b); return p
    }

    static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    static func round(_ width: CGFloat) -> StrokeStyle { StrokeStyle(lineWidth: width, lineCap: .round) }

    // MARK: Whole character

    static func draw(_ f: YumiFrame, in context: GraphicsContext) {
        var body = bodyPath(h: f.h, w: f.w, lean: f.lean)
        // A slime that is still part of him (a fork starting, a merge ending) shares his outline:
        // one body, with one rim, that divides or closes up
        let twins = f.scene.map(YumiScenes.twins) ?? []
        for twin in twins where twin.attached {
            body = body.union(twin.path)
            if let strand = twin.strandPath { body = body.union(strand) }
        }
        let rimShade = across(body.boundingRect, f.rim)

        // .tiltg: the head tilt turns everything around the base
        var tilted = context
        if f.face.tilt != 0 {
            tilted.translateBy(x: 50, y: 76)
            tilted.rotate(by: .degrees(Double(f.face.tilt)))
            tilted.translateBy(x: -50, y: -76)
        }

        // The pictures of the light were drawn for a shape a breath away: stretch them onto this one
        var stored = tilted
        if let light = f.storedLight {
            stored.opacity = f.light
            stored.translateBy(x: 50, y: 76)
            stored.scaleBy(x: f.w / light.w, y: f.h / light.h)
            stored.translateBy(x: -50, y: -76)
            stored.concatenate(light.lean(to: f.lean))
        }

        // .pose: the body follows the lean a little, and jumps
        var pose = tilted
        pose.translateBy(x: -f.lean * 0.12, y: f.y)

        // Light pooled on the floor, then the halo. The arms come out between the two.
        if f.light > 0.01 {
            if let light = f.storedLight {
                stored.draw(light.behind, in: YumiLight.bounds)
            } else {
                drawFloor(f, in: tilted)
                drawArms(f, in: pose)
                drawHalo(f, body: body, in: pose)
            }
        } else {
            drawArms(f, in: pose)
        }

        // The body is pure black, the colour of the island
        pose.fill(body, with: .color(ink))

        var inside = pose
        inside.clip(to: body)
        drawFace(f, in: inside)
        if f.light > 0.01 {
            // Light spilling inside the outline
            if let light = f.storedLight {
                // `inside` is clipped to the body; go back to the space the picture was drawn in
                var spill = inside
                spill.opacity = f.light
                spill.translateBy(x: f.lean * 0.12, y: -f.y)
                spill.translateBy(x: 50, y: 76)
                spill.scaleBy(x: f.w / light.w, y: f.h / light.h)
                spill.translateBy(x: -50, y: -76)
                spill.concatenate(light.lean(to: f.lean))
                spill.draw(light.inner, in: YumiLight.bounds)
            } else {
                drawSpill(f, body: body, in: inside)
            }
            // Soft reflection and its small glint: they slide when the head turns
            let top = 76 - 68 * f.h
            let sx = 35 + f.lean * 0.8 - f.yaw * 12, sy = top + 16 * f.h - f.pitch * 6
            var shine = inside
            shine.opacity = f.light
            shine.translateBy(x: sx, y: sy)
            shine.rotate(by: .degrees(-28))
            shine.scaleBy(x: 19 * f.w, y: 11 * pow(f.h, 0.7))
            shine.fill(circle(0, 0, 1), with: .radialGradient(
                Gradient(colors: [.white.opacity(0.2), .white.opacity(0)]), center: .zero, startRadius: 0, endRadius: 1))

            var glint = inside
            glint.opacity = 0.5 * f.light
            glint.translateBy(x: sx - 4, y: top + 11 * f.h - f.pitch * 6)
            glint.rotate(by: .degrees(-32))
            glint.fill(Path(ellipseIn: CGRect(x: -4.2, y: -1.9, width: 8.4, height: 3.8)), with: .color(.white))
        }

        // The rim, crisp. It is drawn from the left side, over the top, and round the base.
        if f.drawn > 0.001 {
            pose.drawLayer { l in
                l.clipToLayer { fadeTop(&$0) }
                l.stroke(f.drawn >= 0.999 ? body : body.trimmedPath(from: 0, to: f.drawn),
                         with: rimShade, lineWidth: f.rimWidth)
            }
        }

        drawTops(f, in: pose)
        drawProps(f, in: pose)

        if let moment = f.scene {
            for twin in twins {
                YumiScenes.draw(twin, rim: across(twin.path.boundingRect, f.rim), rimWidth: f.rimWidth, in: pose)
            }
            YumiScenes.drawExtras(moment, rim: f.rim, top: 76 - 68 * f.h + f.y,
                                  faceShift: CGPoint(x: f.faceShift.x - f.lean * 0.12, y: f.faceShift.y + f.y), in: tilted)
        }

        // Droplets and smoke live in the tilted space, outside the pose
        for d in f.drops.prefix(12) {
            let r = d.r * min(1, d.life * 3)
            guard r > 0.05 else { continue }
            let c = circle(d.x, d.y, r)
            tilted.fill(c, with: across(c.boundingRect, f.rim))
        }
        for p in f.puffs.prefix(16) {
            let k = p.life / p.max
            var smoke = tilted
            smoke.opacity = 0.5 * k
            smoke.fill(circle(p.x, p.y, p.r * (1 + (1 - k) * 2.2)), with: .color(Color(.sRGB, red: 0.851, green: 0.863, blue: 0.910)))
        }

        drawNotes(f, in: context)
        drawSparks(f, in: context)
        drawZz(f, in: context)
    }

    // MARK: Light

    private static func drawFloor(_ f: YumiFrame, in context: GraphicsContext) {
        let rx = 34 * f.w * (f.air ? 0.7 : 1)
        let floor = CGRect(x: 50 - rx, y: 74, width: rx * 2, height: 8)
        context.drawLayer { l in
            l.opacity = 0.35 * f.light
            l.addFilter(.blur(radius: blur))
            l.fill(Path(ellipseIn: floor), with: across(floor, f.rim))
        }
    }

    private static func drawHalo(_ f: YumiFrame, body: Path, in context: GraphicsContext) {
        context.drawLayer { l in
            l.opacity = f.glow * f.light
            l.clipToLayer { fadeTop(&$0) }
            l.addFilter(.blur(radius: blur))
            l.stroke(body, with: across(body.boundingRect, f.rim), lineWidth: f.rimWidth * 2.2)
        }
    }

    private static func drawSpill(_ f: YumiFrame, body: Path, in context: GraphicsContext) {
        context.drawLayer { l in
            l.opacity = 0.5 * f.light
            l.clipToLayer { lowerHalf(&$0) }
            l.addFilter(.blur(radius: blur))
            l.stroke(body, with: across(body.boundingRect, f.rim), lineWidth: 11)
        }
    }

    /// Floor and halo of a body standing still, for YumiLight.
    static func drawBehind(_ f: YumiFrame, body: Path, in context: GraphicsContext) {
        drawFloor(f, in: context)
        var pose = context
        pose.translateBy(x: -f.lean * 0.12, y: 0)
        drawHalo(f, body: body, in: pose)
    }

    /// Light inside the outline of a body standing still, not yet clipped to it, for YumiLight.
    static func drawInner(_ f: YumiFrame, body: Path, in context: GraphicsContext) {
        var pose = context
        pose.translateBy(x: -f.lean * 0.12, y: 0)
        drawSpill(f, body: body, in: pose)
    }

    // MARK: Face

    private static func drawFace(_ f: YumiFrame, in context: GraphicsContext) {
        // .facepos: the face slides and squashes with the body
        var face = context
        face.translateBy(x: f.faceShift.x, y: f.faceShift.y)
        face.translateBy(x: 50, y: 45)
        face.scaleBy(x: f.faceScale.width, y: f.faceScale.height)
        // .eyes: they grow a little under the pointer
        face.scaleBy(x: f.eyesScale, y: f.eyesScale)
        face.translateBy(x: -50, y: -45)

        for sd: CGFloat in [-1, 1] {
            let left = sd < 0
            let cx = 50 + sd * 13
            let es = left ? f.face.esl : f.face.esr
            let lidTop = left ? f.face.tl : f.face.tr
            let lidAngle = left ? f.face.al : f.face.ar
            let lidBottom = left ? f.face.bl : f.face.br
            let shut = left ? f.face.cl : f.face.cr

            // The eyes sit on a sphere: turning the head slides them sideways and narrows
            // the one going round the edge
            var eg = face
            eg.concatenate(YumiFaceTurn.eye(sd, yaw: f.yaw, pitch: f.pitch))
            eg.translateBy(x: -cx, y: -45)

            // White of the eye, with the blink
            var eye = eg
            eye.translateBy(x: cx, y: 45)
            eye.scaleBy(x: es, y: es * f.blink)
            eye.translateBy(x: -cx, y: -45)

            var white = eye
            white.translateBy(x: cx - 9, y: 34)
            white.scaleBy(x: 18, y: 22)
            white.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: 1, height: 1)), with: .radialGradient(
                Gradient(stops: [.init(color: .white, location: 0.45),
                                 .init(color: Color(.sRGB, red: 0.706, green: 0.749, blue: 0.902), location: 1)]),
                center: CGPoint(x: 0.42, y: 0.36), startRadius: 0, endRadius: 0.75))

            // Pupil and its two reflections
            var pupil = eye
            pupil.translateBy(x: f.pupil.x * 2.2, y: f.pupil.y * 2)
            pupil.translateBy(x: cx, y: 46)
            pupil.scaleBy(x: f.face.ps, y: f.face.ps)
            pupil.translateBy(x: -cx, y: -46)
            pupil.fill(circle(cx, 46, 5.4), with: .color(ink))
            pupil.fill(circle(cx + 1.9, 43.6, 1.7), with: .color(.white))
            pupil.fill(circle(cx - 1.6, 48.2, 0.8), with: .color(.white.opacity(0.7)))

            // Upper lid: a black block that comes down, and tilts for the eyebrows
            var lid = eg
            lid.translateBy(x: cx, y: 45)
            lid.rotate(by: .degrees(Double(lidAngle)))
            lid.translateBy(x: -cx, y: -45)
            lid.translateBy(x: 0, y: lidTop * 25 - 3)
            lid.fill(Path(CGRect(x: cx - 17, y: 8, width: 34, height: 26)), with: .color(ink))

            // Lower lid: the cheek pushing up
            eg.fill(Path(ellipseIn: CGRect(x: cx - 16, y: 56 - lidBottom * 22, width: 32, height: 24)), with: .color(ink))

            // Closed eye
            if shut > 0.01 {
                var p = Path()
                p.move(to: CGPoint(x: cx - 8, y: 45))
                p.addQuadCurve(to: CGPoint(x: cx + 8, y: 45), control: CGPoint(x: cx, y: 51))
                var closed = eg
                closed.opacity = shut
                closed.stroke(p, with: .color(.white), style: round(2.6))
            }
        }
    }

    // MARK: Arms

    private static func drawArms(_ f: YumiFrame, in context: GraphicsContext) {
        // The arm that holds something up during a scene
        if let moment = f.scene, case let raised = YumiScenes.raisedArm(moment), raised > 0.01 {
            var arm = context
            arm.translateBy(x: f.lean * 0.35, y: (1 - f.h) * 24)
            arm.opacity = raised
            let path = line(CGPoint(x: 83, y: 52), CGPoint(x: 100, y: 38))
            arm.stroke(path, with: across(path.boundingRect, f.rim), style: round(12))
            arm.stroke(path, with: .color(ink), style: round(8.4))
        }
        guard let t = f.armTime, let arm = YumiPoseExtras.arm(at: t), arm.opacity > 0.01 else { return }
        var arms = context
        arms.translateBy(x: f.lean * 0.35, y: (1 - f.h) * 24)
        arms.opacity = arm.opacity
        for sd: CGFloat in [-1, 1] {
            let shoulder = CGPoint(x: 50 + sd * 33, y: 52)
            let hand = CGPoint(x: 50 + sd * 45, y: 37)
            var a = arms
            a.translateBy(x: shoulder.x, y: shoulder.y)
            a.rotate(by: .degrees(Double(-sd * arm.angle)))
            a.translateBy(x: -shoulder.x, y: -shoulder.y)
            let path = line(shoulder, hand)
            a.stroke(path, with: across(path.boundingRect, f.rim), style: round(12))
            a.stroke(path, with: .color(ink), style: round(8.4))
        }
    }

    // MARK: Props above the head

    private static func drawTops(_ f: YumiFrame, in context: GraphicsContext) {
        var tops = context
        tops.translateBy(x: f.lean, y: 68 - 68 * f.h)

        if f.costume.onHead {
            YumiCostumes.drawHead(f.costume, .init(time: f.time, lean: f.lean, accent: f.rim[0].color), in: tops)
        }

        if let o = f.props[.headphones], o > 0.01 {
            var c = tops
            c.opacity = o
            var band = Path()
            band.move(to: CGPoint(x: 9, y: 47))
            band.addCurve(to: CGPoint(x: 50, y: 1), control1: CGPoint(x: 9, y: 16), control2: CGPoint(x: 28, y: 1))
            band.addCurve(to: CGPoint(x: 91, y: 47), control1: CGPoint(x: 72, y: 1), control2: CGPoint(x: 91, y: 16))
            c.stroke(band, with: .color(Color(.sRGB, red: 0.169, green: 0.180, blue: 0.247)), style: round(4.2))
            for x: CGFloat in [2, 87] {
                let rect = CGRect(x: x, y: 38, width: 11, height: 20)
                let cup = Path(roundedRect: rect, cornerRadius: 5)
                c.fill(cup, with: .color(Color(.sRGB, red: 0.122, green: 0.133, blue: 0.192)))
                c.stroke(cup, with: across(rect, f.rim), lineWidth: 1.4)
            }
        }

        if let o = f.props[.cloud], o > 0.01 {
            var c = tops
            c.opacity = o
            let grey = GraphicsContext.Shading.color(Color(.sRGB, red: 0.353, green: 0.376, blue: 0.471))
            c.fill(Path(ellipseIn: CGRect(x: 33, y: -15.5, width: 34, height: 13)), with: grey)
            c.fill(circle(40, -12, 7), with: grey)
            c.fill(circle(53, -15.5, 8.5), with: grey)
            c.fill(circle(62, -10.5, 6), with: grey)
            // Rain: four drops falling in a 0.7 s loop, each with its own delay
            let rain = Color(.sRGB, red: 0.498, green: 0.706, blue: 1)
            for (x, delay) in [(CGFloat(40), CGFloat(0)), (48, 0.2), (56, 0.45), (63, 0.1)] {
                let t = f.habitTime - delay
                let p = t < 0 ? 0 : (t / 0.7).truncatingRemainder(dividingBy: 1)
                var drop = c
                drop.opacity = o * (1 - p)
                drop.stroke(line(CGPoint(x: x, y: -1 + 9 * p), CGPoint(x: x, y: 3 + 9 * p)), with: .color(rain), style: round(1.5))
            }
        }
    }

    // MARK: Props on the face

    private static func drawProps(_ f: YumiFrame, in context: GraphicsContext) {
        var props = context
        props.translateBy(x: f.faceShift.x, y: f.faceShift.y)
        props.translateBy(x: 50, y: 45)
        props.scaleBy(x: f.faceScale.width, y: f.faceScale.height)
        props.translateBy(x: -50, y: -45)

        if f.costume.onFace {
            YumiCostumes.drawFace(f.costume, .init(time: f.time, lean: f.lean, accent: f.rim[0].color),
                                  yaw: f.yaw, pitch: f.pitch, eyesScale: f.eyesScale, in: props)
        }

        // What he holds low in front of him stays with the body, which does not turn
        let held = props
        // Everything below is worn on the face: it turns with the head, as the eyes do
        props.concatenate(YumiFaceTurn.face(yaw: f.yaw, pitch: f.pitch))

        if let o = f.props[.smoke], o > 0.01 {
            var c = props
            c.opacity = o
            c.stroke(line(CGPoint(x: 57, y: 60), CGPoint(x: 75.5, y: 64)), with: .color(Color(.sRGB, red: 0.945, green: 0.929, blue: 0.894)), style: round(3.2))
            c.stroke(line(CGPoint(x: 57, y: 60), CGPoint(x: 61, y: 60.9)), with: .color(Color(.sRGB, red: 0.851, green: 0.627, blue: 0.400)), style: round(3.2))
            // The ember breathes; it flares while he takes a drag
            var ember = c
            if f.emberHot {
                ember.fill(circle(76, 64.1, f.emberRadius), with: .color(Color(.sRGB, red: 1, green: 0.753, blue: 0.302)))
            } else {
                let p = (f.time / 1.8).truncatingRemainder(dividingBy: 1)
                ember.opacity = o * yumiKeyframes(p, [(0, 1), (0.5, 0.55), (1, 1)], .easeInOut)
                ember.fill(circle(76, 64.1, f.emberRadius), with: .color(Color(.sRGB, red: 1, green: 0.478, blue: 0.239)))
            }
        }

        if let o = f.props[.coffee], o > 0.01 {
            var c = props
            c.opacity = o
            c.translateBy(x: 8, y: 8)
            // The cup tips towards the mouth for a sip
            c.translateBy(x: 66, y: 60)
            c.rotate(by: .degrees(Double(-30 * f.sip)))
            c.translateBy(x: -3 * f.sip, y: -3 * f.sip)
            c.translateBy(x: -66, y: -60)
            let china = GraphicsContext.Shading.color(Color(.sRGB, red: 0.957, green: 0.961, blue: 0.973))
            var cup = Path()
            cup.move(to: CGPoint(x: 65, y: 54))
            cup.addLine(to: CGPoint(x: 78, y: 54))
            cup.addLine(to: CGPoint(x: 78, y: 60))
            cup.addArc(center: CGPoint(x: 71.5, y: 60), radius: 6.5, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            cup.closeSubpath()
            c.fill(cup, with: china)
            var handle = Path()
            handle.move(to: CGPoint(x: 78, y: 56))
            handle.addQuadCurve(to: CGPoint(x: 83.5, y: 59.6), control: CGPoint(x: 83.5, y: 56))
            handle.addQuadCurve(to: CGPoint(x: 78, y: 63), control: CGPoint(x: 83.5, y: 63.2))
            c.stroke(handle, with: china, lineWidth: 1.9)
            c.stroke(line(CGPoint(x: 66.6, y: 55.4), CGPoint(x: 76.4, y: 55.4)), with: .color(Color(.sRGB, red: 0.420, green: 0.259, blue: 0.149)), style: round(1.7))
        }

        if let o = f.props[.matcha], o > 0.01 {
            var c = props
            c.opacity = o
            c.translateBy(x: 7, y: 8)
            // The bowl tips towards the mouth for a sip, gently
            c.translateBy(x: 70, y: 60)
            c.rotate(by: .degrees(Double(-22 * f.sip)))
            c.translateBy(x: -3 * f.sip, y: -2.5 * f.sip)
            c.translateBy(x: -70, y: -60)
            // A chawan: wide, low, a little uneven, glazed in a warm stone colour
            var bowl = Path()
            bowl.move(to: CGPoint(x: 61.5, y: 54.5))
            bowl.addCurve(to: CGPoint(x: 66.5, y: 64), control1: CGPoint(x: 61.6, y: 59.5), control2: CGPoint(x: 63.4, y: 62.8))
            bowl.addLine(to: CGPoint(x: 74, y: 64))
            bowl.addCurve(to: CGPoint(x: 79, y: 54.2), control1: CGPoint(x: 77.2, y: 62.8), control2: CGPoint(x: 78.9, y: 59.4))
            bowl.closeSubpath()
            let glaze = Color(.sRGB, red: 0.890, green: 0.855, blue: 0.784)
            let shade = Color(.sRGB, red: 0.733, green: 0.682, blue: 0.604)
            c.fill(bowl, with: .linearGradient(Gradient(colors: [glaze, shade]),
                                               startPoint: CGPoint(x: 64, y: 55), endPoint: CGPoint(x: 78, y: 63)))
            // The foot ring, and a run of glaze down the side
            c.fill(Path(roundedRect: CGRect(x: 67.4, y: 63.4, width: 5.8, height: 1.9), cornerRadius: 0.8), with: .color(shade))
            c.stroke(line(CGPoint(x: 75.6, y: 55.6), CGPoint(x: 75.1, y: 59.2)), with: .color(.white.opacity(0.35)), style: round(1.1))
            // The matcha: a soft green surface with its foam
            let surface = CGRect(x: 62, y: 53.3, width: 16.8, height: 3)
            c.fill(Path(ellipseIn: surface), with: .color(Color(.sRGB, red: 0.580, green: 0.737, blue: 0.400)))
            c.fill(Path(ellipseIn: surface.insetBy(dx: 2.6, dy: 0.7)), with: .color(Color(.sRGB, red: 0.698, green: 0.827, blue: 0.494)))
            c.fill(circle(73.4, 54.7, 0.6), with: .color(Color(.sRGB, red: 0.835, green: 0.910, blue: 0.663)))
        }

        drawWorkProps(f, face: props, held: held)

        if let o = f.props[.sunglasses], o > 0.01 {
            // They drop onto his nose in 0.55 s
            let p = YumiCurve.spring(f.habitTime / 0.55)
            var c = props
            c.opacity = o * max(0, min(1, p))
            // They grow with the eyes under the pointer, so the lenses keep covering them
            c.translateBy(x: 50, y: 45)
            c.scaleBy(x: f.eyesScale, y: f.eyesScale)
            c.translateBy(x: -50, y: -45)
            c.translateBy(x: 50, y: 44.5 - 34 * (1 - p))
            c.rotate(by: .degrees(Double(-14 * (1 - p))))
            c.translateBy(x: -50, y: -44.5)
            let dark = GraphicsContext.Shading.color(Color(.sRGB, red: 0.039, green: 0.043, blue: 0.063))
            for x: CGFloat in [24, 52] {
                let rect = CGRect(x: x, y: 37, width: 24, height: 15)
                let lens = Path(roundedRect: rect, cornerRadius: 6)
                c.fill(lens, with: dark)
                c.stroke(lens, with: across(rect, f.rim), lineWidth: 1.6)
            }
            var bridge = Path()
            bridge.move(to: CGPoint(x: 48, y: 42))
            bridge.addQuadCurve(to: CGPoint(x: 52, y: 42), control: CGPoint(x: 50, y: 40.4))
            c.stroke(bridge, with: .color(f.rim[1].color), lineWidth: 1.6)
            var glare = c
            glare.opacity = o * max(0, min(1, p)) * 0.75
            glare.stroke(line(CGPoint(x: 29, y: 47), CGPoint(x: 35, y: 41)), with: .color(.white), style: round(1.5))
            glare.stroke(line(CGPoint(x: 57, y: 47), CGPoint(x: 63, y: 41)), with: .color(.white), style: round(1.5))
        }

        if let o = f.props[.whistle], o > 0.01 {
            var c = props
            c.opacity = o
            c.stroke(circle(52, 61, 2.7), with: .color(.white), lineWidth: 1.7)
        }

        if let o = f.props[.sleep].map({ $0 * f.sleepFx }), o > 0.01 {
            // A bubble swells at his nose and bursts, every 3.2 s
            let p = (f.habitTime / 3.2).truncatingRemainder(dividingBy: 1)
            let scale = yumiKeyframes(p, [(0, 0.15), (0.7, 1), (0.8, 1.25), (0.84, 1.5), (1, 1.5)], .easeInOut)
            let alpha = yumiKeyframes(p, [(0, 1), (0.8, 1), (0.84, 0), (1, 0)], .easeInOut)
            var c = props
            c.opacity = o * alpha
            c.translateBy(x: 53.45, y: 61.55)
            c.scaleBy(x: scale, y: scale)
            c.translateBy(x: -53.45, y: -61.55)
            let blue = Color(.sRGB, red: 0.608, green: 0.722, blue: 1)
            c.fill(circle(58, 57, 6.5), with: .color(blue.opacity(0.22)))
            c.stroke(circle(58, 57, 6.5), with: .color(blue), lineWidth: 1)
        }
    }

    // MARK: Notes, sparks, snoring

    /// `p-zz` of the mock-up: fades in, drifts up and to the right, fades out.
    private static func drift(_ context: GraphicsContext, _ string: String, size: CGFloat, at origin: CGPoint,
                              shading: (CGRect) -> GraphicsContext.Shading, time: CGFloat, period: CGFloat, opacity: CGFloat) {
        guard time >= 0 else { return }
        let p = (time / period).truncatingRemainder(dividingBy: 1)
        let alpha = yumiKeyframes(p, [(0, 0), (0.3, 1), (1, 0)], .easeInOut)
        guard alpha * opacity > 0.01 else { return }
        let e = YumiCurve.easeInOut(p)

        // SVG places text by its baseline
        let glyph = Glyph.of(string, size: size)
        let rect = CGRect(x: origin.x, y: origin.y - glyph.ascent, width: glyph.width, height: glyph.ascent + glyph.descent)

        var c = context
        c.opacity = alpha * opacity
        c.translateBy(x: 8 * e, y: 4 - 18 * e)
        c.translateBy(x: rect.midX, y: rect.midY)
        c.scaleBy(x: 0.6 + 0.5 * e, y: 0.6 + 0.5 * e)
        c.translateBy(x: -rect.midX, y: -rect.midY)
        c.translateBy(x: origin.x, y: origin.y)
        c.fill(glyph.path, with: shading(rect.offsetBy(dx: -origin.x, dy: -origin.y)))
    }

    /// A note or a z as an outline, made once: laying text out again on every picture cost
    /// more than all the rest of a habit.
    private struct Glyph {
        /// The outline, its baseline on y = 0, y down.
        let path: Path
        let width, ascent, descent: CGFloat

        nonisolated(unsafe) private static var made: [String: Glyph] = [:]

        /// SF Pro Rounded Heavy, from the native font of each platform.
        private static func roundedHeavy(_ size: CGFloat) -> CTFont {
            #if canImport(AppKit)
            let base = NSFont.systemFont(ofSize: size, weight: .heavy)
            return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
            #else
            let base = UIFont.systemFont(ofSize: size, weight: .heavy)
            return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
            #endif
        }

        static func of(_ string: String, size: CGFloat) -> Glyph {
            let key = "\(string) \(size)"
            if let glyph = made[key] { return glyph }
            let font = Self.roundedHeavy(size)
            // CTLine picks a fallback font for ♪ and ♫, as Text does
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font]))
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let outline = CGMutablePath()
            for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(), &glyphs)
                CTRunGetPositions(run, CFRange(), &positions)
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard let runFont = attributes[kCTFontAttributeName] else { continue }
                let ctFont = runFont as! CTFont
                for (g, at) in zip(glyphs, positions) {
                    guard let shape = CTFontCreatePathForGlyph(ctFont, g, nil) else { continue }
                    // Core Text draws y up
                    outline.addPath(shape, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: at.x, ty: -at.y))
                }
            }
            let glyph = Glyph(path: Path(outline), width: width, ascent: ascent, descent: descent)
            made[key] = glyph
            return glyph
        }
    }

    private static func drawNotes(_ f: YumiFrame, in context: GraphicsContext) {
        let o = max(f.props[.headphones] ?? 0, f.props[.whistle] ?? 0)
        guard o > 0.01 else { return }
        let shade: (CGRect) -> GraphicsContext.Shading = { across($0, f.rim) }
        drift(context, "♪", size: 11, at: CGPoint(x: 84, y: 22), shading: shade, time: f.habitTime, period: 2.2, opacity: o)
        drift(context, "♫", size: 14, at: CGPoint(x: 93, y: 10), shading: shade, time: f.habitTime - 0.7, period: 2.2, opacity: o)
        drift(context, "♪", size: 10, at: CGPoint(x: 100, y: 26), shading: shade, time: f.habitTime - 1.4, period: 2.2, opacity: o)
    }

    private static func drawZz(_ f: YumiFrame, in context: GraphicsContext) {
        guard let o = f.props[.sleep].map({ $0 * f.sleepFx }), o > 0.01 else { return }
        let blue = Color(.sRGB, red: 0.608, green: 0.722, blue: 1)
        let shade: (CGRect) -> GraphicsContext.Shading = { _ in .color(blue) }
        drift(context, "z", size: 9, at: CGPoint(x: 78, y: 26), shading: shade, time: f.habitTime, period: 2.6, opacity: o)
        drift(context, "z", size: 12, at: CGPoint(x: 86, y: 16), shading: shade, time: f.habitTime - 0.8, period: 2.6, opacity: o)
        drift(context, "Z", size: 15, at: CGPoint(x: 94, y: 6), shading: shade, time: f.habitTime - 1.6, period: 2.6, opacity: o)
    }

    private static let star: Path = {
        let points: [(CGFloat, CGFloat)] = [(0, -5), (1.3, -1.3), (5, 0), (1.3, 1.3), (0, 5), (-1.3, 1.3), (-5, 0), (-1.3, -1.3)]
        var p = Path()
        for (i, pt) in points.enumerated() {
            if i == 0 { p.move(to: CGPoint(x: pt.0, y: pt.1)) } else { p.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
        }
        p.closeSubpath()
        return p
    }()

    private static func drawSparks(_ f: YumiFrame, in context: GraphicsContext) {
        guard let t = f.sparkTime else { return }
        for spark in YumiPoseExtras.sparks {
            guard let k = YumiPoseExtras.spark(at: t - spark.delay), k.opacity > 0.01 else { continue }
            var c = context
            c.opacity = k.opacity
            c.translateBy(x: spark.at.x, y: spark.at.y)
            c.scaleBy(x: spark.scale, y: spark.scale)
            c.translateBy(x: 0, y: k.rise)
            c.rotate(by: .degrees(Double(k.angle)))
            c.scaleBy(x: k.scale, y: k.scale)
            c.fill(star, with: across(CGRect(x: -5, y: -5, width: 10, height: 10), f.rim))
        }
    }

    // MARK: Mini character

    /// `miniSlime` of the mock-up: the resting outline with a thick stroke in the colour of
    /// its module, and two plain eyes. `blink` and `asleep` are the only life it has.
    static func drawMini(color: Color, blink: CGFloat, asleep: Bool, in context: GraphicsContext) {
        let body = bodyPath(h: 1, w: 1, lean: 0)
        context.fill(body, with: .color(ink))
        context.stroke(body, with: .color(color), lineWidth: 8)
        for cx: CGFloat in [37, 63] {
            if asleep {
                var p = Path()
                p.move(to: CGPoint(x: cx - 9, y: 45))
                p.addQuadCurve(to: CGPoint(x: cx + 9, y: 45), control: CGPoint(x: cx, y: 53))
                context.stroke(p, with: .color(.white), style: round(5))
                continue
            }
            var eye = context
            eye.translateBy(x: cx, y: 45)
            eye.scaleBy(x: 1, y: blink)
            eye.translateBy(x: -cx, y: -45)
            eye.fill(Path(ellipseIn: CGRect(x: cx - 10, y: 33, width: 20, height: 24)), with: .color(.white))
            eye.fill(circle(cx + 1, 46, 5.6), with: .color(ink))
        }
    }
}

extension YumiRGB {
    var color: Color { Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b)) }
}
