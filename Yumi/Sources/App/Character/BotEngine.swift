import Foundation
import CoreGraphics
import SwiftUI

// The block below is the first Yumi drawing (CoreGraphics). The greeting and the file-drop
// canvases still use it, and so does the icon generator. The character of the island itself
// is drawn by Character/YumiRenderer.swift, ported from design/maquette/reference.html.

// MARK: - Yumi skin

// >>> YumiSkin
// Yumi's first look (concept 4), used by GreetingCanvasView and UploadCanvasView.
// CoreGraphics only, y pointing down, origin at the body centre.
// design/outils/icones.sh compiles this block on its own to render the icons,
// so keep it free of SwiftUI, AppState and anything outside the markers.

struct YumiRGB: Equatable, Sendable {
    var r: CGFloat, g: CGFloat, b: CGFloat

    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) { self.r = r; self.g = g; self.b = b }

    init(hex: UInt32) {
        self.init(CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
    }

    func mix(_ o: YumiRGB, _ t: CGFloat) -> YumiRGB {
        YumiRGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t)
    }

    func cg(_ alpha: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: alpha) }
}

/// The rim light: three stops running from the left edge to the right edge of the body.
struct YumiRim: Equatable, Sendable {
    var left: YumiRGB, mid: YumiRGB, right: YumiRGB

    /// Resting gradient of the concept sheet: blue, violet, pink.
    static let idle = YumiRim(left: YumiSkin.blue, mid: YumiSkin.violet, right: YumiSkin.rose)

    /// One state (or brand) colour, with a little shading so the rim keeps some depth.
    static func solid(_ c: YumiRGB) -> YumiRim {
        YumiRim(left: c.mix(YumiSkin.white, 0.34), mid: c, right: c.mix(YumiSkin.white, 0.10))
    }

    func mix(_ o: YumiRim, _ t: CGFloat) -> YumiRim {
        YumiRim(left: left.mix(o.left, t), mid: mid.mix(o.mid, t), right: right.mix(o.right, t))
    }
}

/// One eye. Everything is a number so two expressions can be blended.
struct YumiEye: Equatable, Sendable {
    var scale: CGFloat = 1
    var lidTop: CGFloat = 0      // 0…1 of the eye height covered by the upper lid
    var lidBottom: CGFloat = 0   // 0…1 covered by the lower lid (arched, the cheek pushes up)
    var slant: CGFloat = 0       // upper lid slope: > 0 inner side lower, < 0 outer side lower
    var arc: CGFloat = 0         // closed eye: +1 bent upwards (smile), -1 bent downwards (sleep)
    var pupil: CGFloat = 1       // pupil scale
    var px: CGFloat = 0          // pupil offset added to the gaze, -1…1
    var py: CGFloat = 0
    var heart: CGFloat = 0       // 0…1 pupil replaced by a heart
    var sparkle: CGFloat = 0     // 0…1 second reflection

    func mix(_ o: YumiEye, _ t: CGFloat) -> YumiEye {
        func l(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        return YumiEye(scale: l(scale, o.scale), lidTop: l(lidTop, o.lidTop), lidBottom: l(lidBottom, o.lidBottom),
                       slant: l(slant, o.slant), arc: l(arc, o.arc), pupil: l(pupil, o.pupil),
                       px: l(px, o.px), py: l(py, o.py), heart: l(heart, o.heart), sparkle: l(sparkle, o.sparkle))
    }
}

struct YumiEyes: Equatable, Sendable {
    var left = YumiEye()
    var right = YumiEye()
    var gaze: CGFloat = 1        // how much of the look direction reaches the pupils

    func mix(_ o: YumiEyes, _ t: CGFloat) -> YumiEyes {
        YumiEyes(left: left.mix(o.left, t), right: right.mix(o.right, t), gaze: gaze + (o.gaze - gaze) * t)
    }
}

enum YumiSkin {
    // Palette of the concept sheet
    static let ink    = YumiRGB(hex: 0x0B0F1A)
    static let indigo = YumiRGB(hex: 0x2A2A8C)
    static let blue   = YumiRGB(hex: 0x5B8CFF)
    static let violet = YumiRGB(hex: 0xC77DFF)
    static let rose   = YumiRGB(hex: 0xFF8AD0)
    static let white  = YumiRGB(hex: 0xFFFFFF)
    static let heart  = YumiRGB(hex: 0xFF5C9A)

    // Body half-size in units of R (R is half of the "diameter" used by the layouts)
    static let bodyHW: CGFloat = 1.14
    static let bodyHH: CGFloat = 0.88
    // The box the body morphs into while it waits for a file
    static let boxHW: CGFloat = 1.0
    static let boxHH: CGFloat = 0.94
    static let boxCorner: CGFloat = 0.42

    // MARK: Silhouette

    /// Point of the dome outline for angle `a`, in a -1…1 box (y down): round on top,
    /// wider and almost flat at the base.
    static func domePoint(_ a: CGFloat) -> CGPoint {
        let ca = cos(a), sa = sin(a)
        let n: CGFloat = sa < 0 ? domeTop : domeBase
        var x = (ca < 0 ? -1 : 1) * pow(abs(ca), 2 / n)
        let y = (sa < 0 ? -1 : 1) * pow(abs(sa), 2 / n)
        x *= domeTaper(y) / domeWidest
        return CGPoint(x: x, y: y)
    }

    private static let domeTop: CGFloat = 2.1     // superellipse exponent above the centre
    private static let domeBase: CGFloat = 3.1    // and below: squarer, so the base reads flat
    private static func domeTaper(_ y: CGFloat) -> CGFloat { 1 - 0.25 * pow((1 - y) / 2, 1.25) }

    /// Widest half-width of the tapered outline before normalisation.
    private static let domeWidest: CGFloat = {
        var m: CGFloat = 0
        for i in 0...200 {
            let y = CGFloat(i) / 200
            let x = pow(1 - pow(y, domeBase), 1 / domeBase) * domeTaper(y)
            m = max(m, x)
        }
        return m
    }()

    /// Body outline. `morph` 0 is the dome, 1 the rounded box of half-size `boxHW` × `boxHH`.
    static func bodyPath(hw: CGFloat, hh: CGFloat, morph: CGFloat = 0,
                         boxHW: CGFloat = 0, boxHH: CGFloat = 0, boxCorner: CGFloat = 0) -> CGPath {
        let n = 96
        let m = max(0, min(1, morph))
        let path = CGMutablePath()
        for i in 0..<n {
            let a = CGFloat(i) / CGFloat(n) * .pi * 2
            let d = domePoint(a)
            var p = CGPoint(x: d.x * hw, y: d.y * hh)
            if m > 0.005 {
                let b = boxPoint(ca: cos(a), sa: sin(a), W: boxHW, H: boxHH, cr: boxCorner)
                p = CGPoint(x: p.x + (b.x - p.x) * m, y: p.y + (b.y - p.y) * m)
            }
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    /// Where the ray of direction (ca, sa) leaves a rounded rectangle of half-size W × H.
    static func boxPoint(ca: CGFloat, sa: CGFloat, W: CGFloat, H: CGFloat, cr: CGFloat) -> CGPoint {
        let eps: CGFloat = 1e-6
        let kx: CGFloat = ca >= 0 ? 1 : -1
        let ky: CGFloat = sa >= 0 ? 1 : -1
        let cx = kx * (W - cr)
        let cy = ky * (H - cr)

        let dot  = ca * cx + sa * cy
        let disc = dot * dot - (cx * cx + cy * cy - cr * cr)
        if disc >= 0 {
            let t = dot + sqrt(disc)
            if t > eps {
                let px = ca * t, py = sa * t
                if abs(px) >= W - cr - eps && abs(py) >= H - cr - eps { return CGPoint(x: px, y: py) }
            }
        }
        if abs(sa) > eps {
            let t = (ky * H) / sa
            if t > eps {
                let x = ca * t
                if abs(x) <= W - cr + eps { return CGPoint(x: x, y: ky * H) }
            }
        }
        if abs(ca) > eps {
            let t = (kx * W) / ca
            if t > eps {
                let y = sa * t
                if abs(y) <= H - cr + eps { return CGPoint(x: kx * W, y: y) }
            }
        }
        return CGPoint(x: kx * W, y: ky * H)
    }

    // MARK: Body

    private static func gradient(_ stops: [(YumiRGB, CGFloat, CGFloat)]) -> CGGradient? {
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var comps: [CGFloat] = []
        var locs: [CGFloat] = []
        for (c, alpha, loc) in stops {
            comps += [c.r, c.g, c.b, alpha]
            locs.append(loc)
        }
        return CGGradient(colorSpace: cs, colorComponents: comps, locations: locs, count: stops.count)
    }

    /// Rim thickness for a body of unit R. Never under a point, so the outline survives at 12 pt.
    static func rimWidth(_ R: CGFloat) -> CGFloat { max(R * 0.085, 1.0) }

    /// Black body carried by its rim light. The island is black too: without the rim the
    /// silhouette disappears, so the rim is drawn crisp, with a soft bloom behind it.
    /// `glow` (0…1) adds a halo outside the body; `shine` the soft reflection of the sheet.
    static func drawBody(_ ctx: CGContext, path: CGPath, hw: CGFloat, hh: CGFloat, R: CGFloat,
                         rim: YumiRim, glow: CGFloat = 0, shine: Bool = true, alpha: CGFloat = 1) {
        if glow > 0.01 {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: R * 0.5, color: rim.mid.cg(0.60 * glow * alpha))
            ctx.addPath(path)
            ctx.setFillColor(ink.cg(alpha))
            ctx.fillPath()
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        if alpha < 1 { ctx.setAlpha(alpha) }

        if let g = gradient([(ink.mix(indigo, 0.16), 1, 0), (ink, 1, 0.55), (ink.mix(YumiRGB(0, 0, 0), 0.35), 1, 1)]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: -hh), end: CGPoint(x: 0, y: hh),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }

        // Rim: the body minus a copy of itself pushed up and squeezed, which leaves a
        // crescent that is thicker at the base and on the sides than at the top.
        let t = rimWidth(R)
        let rimGradient = gradient([(rim.left, 1, 0), (rim.mid, 1, 0.52), (rim.right, 1, 1)])
        // A stack of wider, fainter crescents stands in for a blur behind the crisp one.
        // More of them on a large body, where the steps would show.
        let bloom = R > 9 ? min(32, max(9, Int(R / 5))) : 2
        var layers: [(CGFloat, CGFloat)] = (0..<bloom).map { i in
            let k = CGFloat(i) / CGFloat(bloom - 1)   // 0 widest, 1 narrowest
            return (1.5 + (1 - k) * (R > 9 ? 3.4 : 0.6), R > 9 ? (0.015 + 0.06 * k) * 9 / CGFloat(bloom) : 0.16)
        }
        layers.append((1, 1))
        for (k, a) in layers {
            let side = t * k, bottom = t * k * 1.15, top = t * (0.30 + (k - 1) * 0.25)
            var tr = CGAffineTransform(translationX: 0, y: (top - bottom) / 2)
                .scaledBy(x: max(0.05, 1 - side / hw), y: max(0.05, 1 - (top + bottom) / (2 * hh)))
            guard let inner = path.copy(using: &tr), let g = rimGradient else { continue }
            ctx.saveGState()
            ctx.addPath(path)
            ctx.addPath(inner)
            ctx.clip(using: .evenOdd)
            ctx.setAlpha(a * alpha)
            ctx.drawLinearGradient(g, start: CGPoint(x: -hw, y: -hh * 0.35), end: CGPoint(x: hw, y: hh * 0.55),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }

        if shine && R > 9, let g = gradient([(blue.mix(white, 0.35), 0.20, 0), (blue, 0, 1)]) {
            let c = CGPoint(x: -hw * 0.40, y: -hh * 0.52)
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: R * 0.62, options: [])
        }
        ctx.restoreGState()
    }

    // MARK: Eyes

    /// Eyes grow relative to the body when it gets small (compact island, mini characters).
    static func eyeBoost(_ R: CGFloat) -> CGFloat {
        let k = max(0, min(1, (R - 7) / 6))
        return 1.35 - 0.35 * (k * k * (3 - 2 * k))
    }

    /// Two white ovals with a round black pupil and a small reflection. `gaze` is the look
    /// direction (-1…1, y down), `open` the blink (1 open), `scale` the tweened eye scale.
    static func drawEyes(_ ctx: CGContext, R: CGFloat, eyes: YumiEyes, gaze: CGPoint = .zero,
                         open: CGFloat = 1, scale: CGFloat = 1, offset: CGPoint = .zero) {
        let boost = eyeBoost(R)
        let spacing = R * 0.34 * (1 + (boost - 1) * 0.6)
        for side: CGFloat in [-1, 1] {
            let e = side < 0 ? eyes.left : eyes.right
            let w = R * 0.50 * boost * scale * e.scale
            let h = R * 0.64 * boost * scale * e.scale
            ctx.saveGState()
            ctx.translateBy(x: offset.x + side * spacing, y: offset.y - R * 0.10)
            drawEye(ctx, e, side: side, w: w, h: h, R: R,
                    gaze: CGPoint(x: gaze.x * eyes.gaze, y: gaze.y * eyes.gaze), open: open)
            ctx.restoreGState()
        }
    }

    private static func drawEye(_ ctx: CGContext, _ e: YumiEye, side: CGFloat, w: CGFloat, h: CGFloat,
                                R: CGFloat, gaze: CGPoint, open: CGFloat) {
        let o = max(0, min(1, open)) * (1 - min(1, abs(e.arc)))

        // Closed: a white stroke, bent like a smile or like a sleeping eye.
        if o < 0.14 {
            let lw = max(w * 0.22, 0.9)
            let bend = e.arc * h * 0.28
            let x = max(w / 2 - lw / 2, lw * 0.3)
            ctx.setStrokeColor(white.cg())
            ctx.setLineWidth(lw)
            ctx.setLineCap(.round)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: -x, y: bend / 2))
            ctx.addQuadCurve(to: CGPoint(x: x, y: bend / 2), control: CGPoint(x: 0, y: -bend * 1.5))
            ctx.strokePath()
            return
        }

        let eh = h * o
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: -w / 2, y: -eh / 2, width: w, height: eh))
        ctx.clip()

        if e.lidTop > 0.001 || e.lidBottom > 0.001 || abs(e.slant) > 0.001 {
            let top = -eh / 2 + e.lidTop * eh
            func lid(_ x: CGFloat) -> CGFloat { top + e.slant * (-side) * (x / (w / 2)) * eh * 0.30 }
            let apex = eh / 2 - e.lidBottom * eh
            let edge = apex + e.lidBottom * eh * 0.9
            ctx.beginPath()
            ctx.move(to: CGPoint(x: -w, y: lid(-w)))
            ctx.addLine(to: CGPoint(x: w, y: lid(w)))
            ctx.addLine(to: CGPoint(x: w, y: edge))
            ctx.addLine(to: CGPoint(x: w * 0.56, y: edge))
            ctx.addQuadCurve(to: CGPoint(x: -w * 0.56, y: edge), control: CGPoint(x: 0, y: 2 * apex - edge))
            ctx.addLine(to: CGPoint(x: -w, y: edge))
            ctx.closePath()
            ctx.clip()
        }

        ctx.setFillColor(white.cg())
        ctx.fill(CGRect(x: -w, y: -h, width: w * 2, height: h * 2))

        // Pupil
        let pr = w * 0.33 * e.pupil
        var gx = gaze.x + e.px, gy = gaze.y + e.py
        let len = hypot(gx, gy)
        if len > 1 { gx /= len; gy /= len }
        let cx = gx * max(0, w / 2 - pr) * 0.92
        let cy = gy * max(0, h / 2 - pr) * 0.82
        if e.heart < 0.99 {
            ctx.setFillColor(ink.cg(1 - e.heart))
            ctx.fillEllipse(in: CGRect(x: cx - pr, y: cy - pr, width: pr * 2, height: pr * 2))
        }
        if e.heart > 0.01 {
            let s = pr * 1.55
            ctx.beginPath()
            ctx.move(to: CGPoint(x: cx, y: cy + s * 0.62))
            ctx.addCurve(to: CGPoint(x: cx, y: cy - s * 0.30),
                         control1: CGPoint(x: cx - s * 1.25, y: cy - s * 0.10),
                         control2: CGPoint(x: cx - s * 0.55, y: cy - s * 0.95))
            ctx.addCurve(to: CGPoint(x: cx, y: cy + s * 0.62),
                         control1: CGPoint(x: cx + s * 0.55, y: cy - s * 0.95),
                         control2: CGPoint(x: cx + s * 1.25, y: cy - s * 0.10))
            ctx.closePath()
            ctx.setFillColor(heart.cg(e.heart))
            ctx.fillPath()
        }
        // Reflections, dropped when they would be under half a point
        if R >= 8 {
            let rr = pr * 0.34
            ctx.setFillColor(white.cg())
            ctx.fillEllipse(in: CGRect(x: cx + pr * 0.36 - rr, y: cy - pr * 0.38 - rr, width: rr * 2, height: rr * 2))
            if e.sparkle > 0.01 {
                let r2 = pr * 0.22 * e.sparkle
                ctx.fillEllipse(in: CGRect(x: cx - pr * 0.42 - r2, y: cy + pr * 0.36 - r2, width: r2 * 2, height: r2 * 2))
            }
        }
        ctx.restoreGState()
    }

    /// Soft pink cheeks under the eyes.
    static func drawBlush(_ ctx: CGContext, R: CGFloat, amount: CGFloat, offset: CGPoint = .zero) {
        guard amount > 0.01, let g = gradient([(heart, 0.60 * min(1, amount), 0), (heart, 0, 1)]) else { return }
        for side: CGFloat in [-1, 1] {
            ctx.saveGState()
            ctx.translateBy(x: offset.x + side * R * 0.66, y: offset.y + R * 0.30)
            ctx.scaleBy(x: 1, y: 0.6)
            ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: R * 0.26, options: [])
            ctx.restoreGState()
        }
    }

    // MARK: Arms and mouth

    /// A small arm: a capsule of the same material as the body, centred on the current origin.
    static func drawArm(_ ctx: CGContext, length: CGFloat, thickness: CGFloat, R: CGFloat, rim: YumiRim) {
        guard length > 0.3, thickness > 0.3 else { return }
        let rect = CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness)
        let r = min(length, thickness) / 2
        let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        drawBody(ctx, path: path, hw: length / 2, hh: thickness / 2, R: R * 0.7, rim: rim, shine: false)
    }

    /// The mouth that opens on top of the box: lit from the inside by the rim colour.
    static func drawMouth(_ ctx: CGContext, body: CGPath, rect: CGRect, rim: YumiRim, alpha: CGFloat = 1) {
        guard rect.height > 0.3, rect.width > 0.3 else { return }
        let r = min(rect.width / 2, rect.height / 2)
        let hole = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        ctx.setAlpha(alpha)
        ctx.saveGState()
        ctx.addPath(hole)
        ctx.clip()
        if let g = gradient([(YumiRGB(0, 0, 0), 1, 0), (indigo.mix(rim.mid, 0.35), 1, 1)]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        ctx.restoreGState()
        if rect.height > 2 {
            ctx.addPath(hole)
            ctx.setStrokeColor(rim.mid.mix(white, 0.25).cg(0.9))
            ctx.setLineWidth(1)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // MARK: Whole character

    /// Yumi at rest, centred on the origin: used for the mini characters of the greeting
    /// and by the icon generator.
    static func drawFigure(_ ctx: CGContext, R: CGFloat, rim: YumiRim = .idle, eyes: YumiEyes = YumiEyes(),
                           gaze: CGPoint = .zero, glow: CGFloat = 0) {
        let hw = R * bodyHW, hh = R * bodyHH
        let path = bodyPath(hw: hw, hh: hh)
        drawBody(ctx, path: path, hw: hw, hh: hh, R: R, rim: rim, glow: glow)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        drawEyes(ctx, R: R, eyes: eyes, gaze: gaze)
        ctx.restoreGState()
    }
}
// <<< YumiSkin

// MARK: - Cadence

/// How often Yumi needs a new picture. He only costs something when he moves.
enum YumiCadence: Comparable {
    /// Nothing changes (deep sleep): no picture at all.
    case still
    /// Only the breathing: about fifteen pictures a second.
    case low
    /// A habit that lasts (smoke, notes, steam, the cloud, the z): thirty pictures a second.
    /// It moves slowly and evenly, so the eye sees no difference with every frame.
    case habit
    /// A pose, a face changing, a look moving, an animated habit: every frame.
    case full
}

extension YumiCadence {
    /// Shortest time between two pictures, nil for every frame of the screen.
    var interval: Double? {
        switch self {
        case .full: return nil
        case .habit: return 1.0 / 30
        case .low, .still: return 1.0 / 15
        }
    }
}

// MARK: - Bot engine

/// The character as the rest of the app drives it. The soft body, the faces, the poses and the
/// habits are ports of design/maquette/reference.html (see Character/). This class decides
/// which of them to show, from the island state and from the commands of
/// Contracts/CharacterCommands.swift, and eases the face the way the CSS of the mock-up does.
///
/// Who wins: a habit brings its own face and rim colour; without a habit, a commanded mood or
/// rim tone applies; without a command, the island state decides (see `look(for:receiving:)`).
@MainActor
final class BotEngine: ObservableObject {
    var isMini: Bool = false
    var bodyColor: CGColor? = nil      // colour of a mini character
    /// Extra height the caller adds above its frame; the body sits half of it lower.
    var particleOverhang: CGFloat = 0

    /// Direction of the pointer seen from Yumi, -1…1 on both axes, y down. Set by the view.
    var pointer = CGPoint.zero
    /// Eye scale target (1.08 while the pointer is on him).
    var tgEs: CGFloat = 1 { didSet { if tgEs != oldValue { wake() } } }

    /// The rate the view should redraw at. Published only when it changes.
    @Published private(set) var cadence: YumiCadence = .full {
        didSet {
            #if DEBUG
            // `YUMI_TRACE_CADENCE=1` prints every change of cadence of the main character
            if cadence != oldValue, !isMini, ProcessInfo.processInfo.environment["YUMI_TRACE_CADENCE"] != nil {
                fputs(String(format: "YUMI cadence %.2f s: \(cadence)\n", clock), stderr)
            }
            #endif
        }
    }
    private var calmSince: Double?
    #if DEBUG
    private var traceSecond = -1
    #endif
    private var cadenceChangeQueued = false
    /// Simulated time of the last command: he was just told something, he is not at rest.
    private var lastStir: Double = 0
    /// Seconds asleep before the sleep goes deep: the bubble and the z fade, and he stops.
    private static let deepSleepAfter: Double = 30
    private var sleepFx = YumiTransition(1)

    /// Pixels per point of the screen he is drawn on. Set by the view.
    var displayScale: CGFloat = 2
    // The blurred light, kept from one picture to the next while the shape only breathes
    private var light_: YumiLight?
    private var lightKey: [CGFloat] = []
    private var lightQueued = false
    private var lightBuiltAt: Double = -1

    private(set) var state: BotState = .idle
    private let blob = YumiBlob()

    // Simulated time, in seconds. Advanced only by advance(to:), so a paused view pauses Yumi.
    private var clock: Double = 0
    private var lastDate: Date?

    // Commands of the character contract
    private var habitCommand: YumiHabit?
    private var moodCommand: YumiMood?
    private var rimCommand: YumiRimTone?
    private var gazeCommand: CGPoint?
    private var lit = true
    /// A file or a window is being handed over: he looks up, surprised.
    private var receiving = false

    // A face shown for a moment (emotes of the island, a slap)
    private var emote: (face: YumiFace, until: Double)?
    private var slapTimes: [Double] = []

    // Pose in progress, for the arms and the sparks
    private var pose: YumiPose?
    private var poseStart: Double = 0
    private var habitStart: Double = 0
    // Scene in progress (an outside event)
    private var scene: (kind: YumiScene, start: Double, amount: Int)?

    // Idle life: now and then he glances somewhere on his own
    private var glance: CGPoint?
    private var glanceUntil: Double = 0
    private var nextGlance: Double = 6.5

    private var blinkPhase = Double.random(in: 0..<5.4)
    private var blinkAt: Double?

    // Eased values: the CSS transitions of the mock-up
    private var esl = YumiTransition(1), esr = YumiTransition(1), ps = YumiTransition(1)
    private var tl = YumiTransition(0), tr = YumiTransition(0)
    private var al = YumiTransition(0), ar = YumiTransition(0)
    private var bl = YumiTransition(0), br = YumiTransition(0)
    private var cl = YumiTransition(0), cr = YumiTransition(0)
    private var tilt = YumiTransition(0)
    private var lx = YumiTransition(0), ly = YumiTransition(0)
    private var eyes = YumiTransition(1)
    private var rimStops: [[YumiTransition]] = BotEngine.stops(.calm, accent: .current()).map { [YumiTransition($0.r), YumiTransition($0.g), YumiTransition($0.b)] }
    /// The island's colour (his rim at rest) and what he wears, from the settings.
    private var accent = IslandAccent.current()
    private var costume = YumiCostume.current()
    private var rimWidth = YumiTransition(2.6)
    private var rimWidthSet = false
    private var drawn = YumiTransition(1)
    private var light = YumiTransition(1)
    private var props: [YumiHabit: YumiTransition] = [:]
    private var ember = YumiTransition(1.9)
    private var sip = YumiTransition(0)

    // MARK: - Commands (Contracts/CharacterCommands.swift)

    func play(_ newPose: YumiPose) {
        guard !isMini else { return }
        #if DEBUG
        if ProcessInfo.processInfo.environment["YUMI_TRACE_CADENCE"] == "3" {
            fputs(String(format: "YUMI play %.2f s: \(newPose)\n", clock), stderr)
        }
        #endif
        wake()
        blob.play(newPose, now: clock * 1000)
        pose = newPose
        poseStart = clock
    }

    /// Contracts/EventAnimations.swift: plays the scene once. He then goes back to what he
    /// was doing: the habit keeps its prop during the scene and takes over again after it.
    /// `count` events at once play one scene, a little larger.
    func playScene(_ kind: YumiScene, count: Int = 1) {
        guard !isMini else { return }
        wake()
        let amount = max(1, min(4, count))
        blob.run(YumiBlob.steps(for: kind, amount: amount), now: clock * 1000)
        pose = nil
        scene = (kind, clock, amount)
    }

    func setHabit(_ habit: YumiHabit?) {
        guard habit != habitCommand else { return }
        habitCommand = habit
        wake()
    }

    /// A new mood replaces whatever face a pose had put on, and frees the gaze, as `setMood`
    /// does in the mock-up. Send the gaze after the mood.
    func setMood(_ mood: YumiMood?) {
        moodCommand = mood
        gazeCommand = nil
        blob.tempFace = nil
        emote = nil
        wake()
    }

    /// The colour of the island or what he wears changed in the settings.
    func setLook(accent: IslandAccent, costume: YumiCostume) {
        guard accent != self.accent || costume != self.costume else { return }
        self.accent = accent
        self.costume = costume
        wake()
    }

    /// The stops of his rim for a tone: at rest, the island's colour; the tones of a state stay.
    static func stops(_ tone: YumiRimTone, accent: IslandAccent) -> [YumiRGB] {
        tone == .calm ? accent.restStops.map { YumiRGB(hex: $0) } : tone.stops
    }

    func setRim(_ tone: YumiRimTone?) {
        guard tone != rimCommand else { return }
        rimCommand = tone
        wake()
    }

    /// Unlit, the body is black on the black island: only the eyes show. When the light
    /// comes back the rim draws itself round him and the glow blooms.
    func setLit(_ on: Bool) {
        guard on != lit else { return }
        lit = on
        wake()
        if on {
            drawn.set(1, at: clock, over: 0.8, .draw)
            light.set(1, at: clock, over: 0.7, .ease)
        } else {
            drawn.jump(0)
            light.jump(0)
        }
    }

    func setGaze(_ point: CGPoint?) {
        guard point != gazeCommand else { return }
        gazeCommand = point
        wake()
    }

    // MARK: - Island state and legacy notifications

    func setState(_ newState: BotState, force: Bool = false) {
        guard state != newState || force else { return }
        let changed = state != newState
        #if DEBUG
        if !isMini, ProcessInfo.processInfo.environment["YUMI_TRACE_CADENCE"] == "3" {
            fputs(String(format: "YUMI state %.2f s: \(state) -> \(newState) force \(force)\n", clock), stderr)
        }
        #endif
        state = newState
        wake()
        emote = nil
        blob.tempFace = nil
        guard changed, !isMini, habitCommand != .sleep else { return }
        switch newState {
        case .finished:         play(.celebrate)
        case .error:            play(.squash)
        case .approval, .dizzy: play(.shake)
        default:
            // No pop for the other states: they come and go with every session of Claude Code
            // (idle, working, idle again), and each pop forced full cadence for nothing. The
            // island and the agent's look send a pose themselves when a view or an activity
            // calls for one.
            break
        }
    }

    /// The island is waiting for a file or a window to be dropped on it.
    func setReceiving(_ on: Bool) {
        guard on != receiving else { return }
        receiving = on
        wake()
        if on { play(.stretch) }
    }

    func blink() { blinkAt = clock; wake() }

    func gulp() {
        play(.boing)
        emote = (.happy, clock + 0.8)
        wake()
    }

    /// The character's own sounds, the same WAV files on the Mac and the iPhone.
    private func playSound(_ name: String) {
        SoundEngine.shared.play(name)
    }

    func greet() {
        play(.wave)
        playSound("greet")
    }

    /// A click on Yumi: he bounces. Three in a row and he gets dizzy.
    func slap() {
        guard state != .dizzy else { return }
        slapTimes = slapTimes.filter { clock - $0 < 1.7 }
        slapTimes.append(clock)
        playSound("slap")
        play(.boing)
        if slapTimes.count >= 3 {
            slapTimes = []
            NotificationCenter.default.post(name: .botDizzy, object: nil)
        } else {
            triggerEmote(.annoyed)
        }
    }

    func triggerEmote(_ kind: BotEmote, duration: Double = 1.8) {
        wake()
        switch kind {
        case .love:
            emote = (.happy, clock + duration)
            play(.pop)
        case .surprised:
            emote = (.surprised, clock + duration)
            play(.pop)
        case .proud, .happy:
            emote = (.happy, clock + duration)
        case .wink:
            emote = (.wink, clock + duration)
        case .yawn:
            emote = (.asleep, clock + duration)
        case .annoyed:
            emote = (.annoyed, clock + 0.8)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                self.playSound("annoyed")
            }
        }
    }

    /// Face and rim colour for an island state, when nothing else was commanded.
    private static func look(for state: BotState, receiving: Bool) -> (mood: YumiMood, rim: YumiRimTone) {
        if receiving { return (.surprised, .calm) }
        switch state {
        case .idle:      return (.neutral, .calm)
        case .working:   return (.focused, .work)
        case .thinking:  return (.thinking, .think)
        case .searching: return (.curious, .think)
        case .approval:  return (.surprised, .warn)
        case .question:  return (.curious, .warn)
        case .error:     return (.worried, .error)
        case .finished:  return (.happy, .done)
        case .ratelimit: return (.worried, .warn)
        case .sleeping:  return (.asleep, .calm)
        case .dizzy:     return (.surprised, .joy)
        }
    }

    // MARK: - Frame (called from the view's TimelineView)

    func advance(to date: Date) {
        let elapsed = lastDate.map { max(0, date.timeIntervalSince($0)) } ?? 0
        lastDate = date
        // After a pause he picks up where he was. Otherwise he keeps real time, in steps of
        // 33 ms at most (the cap of the mock-up), so the springs behave the same at any cadence.
        var left = elapsed > 0.5 ? 0.033 : elapsed
        if isMini { clock += left; return }
        while left > 0 {
            let dt = min(0.033, left)
            left -= dt
            step(dt)
        }
        updateCadence()
    }

    private func step(_ dt: Double) {
        clock += dt

        // A sleeping island state falls asleep by itself
        let habit = habitCommand ?? (state == .sleeping ? .sleep : nil)
        if habit != blob.habit {
            blob.setHabit(habit)
            habitStart = clock
            emote = nil
        }

        let fromState = BotEngine.look(for: state, receiving: receiving)
        let mood = habit?.face ?? moodCommand?.face ?? fromState.mood.face
        let tone = habit?.rim ?? rimCommand ?? fromState.rim

        if let e = emote, clock >= e.until { emote = nil }
        if let p = pose, clock - poseStart >= p.duration { pose = nil }
        if let s = scene, clock - s.start >= s.kind.duration { scene = nil }
        let face = blob.tempFace ?? emote?.face ?? mood

        if clock >= nextGlance {
            nextGlance = clock + 6.5
            if habit == nil, pose == nil, face.look == nil, gazeCommand == nil, lit {
                glance = CGPoint(x: .random(in: -1...1), y: .random(in: -0.6...0.6))
                glanceUntil = clock + 0.9
            }
        }
        if glance != nil, clock >= glanceUntil { glance = nil }

        // Where he looks: a face can pin the gaze, then a command, then a glance, then the pointer
        let fixed = face.look ?? gazeCommand ?? glance
        let look = fixed ?? pointer
        blob.lookX = look.x
        blob.lookY = look.y
        if fixed == nil { blob.gaze = pointer.x * 2.5 }

        blob.step(dt: CGFloat(dt), now: clock * 1000)

        // Durations and curves below are the CSS transitions of the mock-up
        let now = clock
        esl.set(face.esl, at: now, over: 0.26, .lid)
        esr.set(face.esr, at: now, over: 0.26, .lid)
        tl.set(face.tl, at: now, over: 0.26, .lid)
        tr.set(face.tr, at: now, over: 0.26, .lid)
        al.set(face.al, at: now, over: 0.26, .lid)
        ar.set(face.ar, at: now, over: 0.26, .lid)
        bl.set(face.bl, at: now, over: 0.26, .lid)
        br.set(face.br, at: now, over: 0.26, .lid)
        ps.set(face.ps, at: now, over: 0.26, .spring)
        cl.set(face.cl, at: now, over: 0.12, .ease)
        cr.set(face.cr, at: now, over: 0.12, .ease)
        tilt.set(face.tilt, at: now, over: 0.4, .spring)
        lx.set(look.x, at: now, over: fixed != nil ? 0.3 : 0.14, fixed != nil ? .spring : .easeOut)
        ly.set(look.y, at: now, over: fixed != nil ? 0.3 : 0.14, fixed != nil ? .spring : .easeOut)
        eyes.set(tgEs, at: now, over: 0.25, .spring)
        for (i, stop) in BotEngine.stops(tone, accent: accent).enumerated() {
            rimStops[i][0].set(stop.r, at: now, over: 0.5, .ease)
            rimStops[i][1].set(stop.g, at: now, over: 0.5, .ease)
            rimStops[i][2].set(stop.b, at: now, over: 0.5, .ease)
        }
        for h in YumiHabit.allCases {
            props[h, default: YumiTransition(0)].set(h == habit ? 1 : 0, at: now, over: 0.25, .ease)
        }
        ember.set(blob.drag ? 3 : 1.9, at: now, over: 0.3, .ease)
        sip.set(blob.sip ? 1 : 0, at: now, over: 0.35, .spring)
        sleepFx.set(isDeepAsleep ? 0 : 1, at: now, over: 0.7, .ease)
    }

    // MARK: - Stored light

    /// The blurred light drawn earlier, if it fits this picture: same colours, same size, a
    /// shape within a breath of the one it was drawn for, nothing in the way. Otherwise nil,
    /// and once the body has come to rest a new one is prepared for the next pictures.
    private func storedLight(for f: YumiFrame, unit: CGFloat) -> YumiLight? {
        guard f.y == 0, !f.air, f.armTime == nil, f.scene == nil, f.glow == 0.85, f.drawn >= 0.999 else { return nil }
        let key = f.rim.flatMap { [$0.r, $0.g, $0.b] } + [f.rimWidth, unit, displayScale]
        if let l = light_, key == lightKey, abs(f.h - l.h) <= 0.1, abs(f.lean - l.lean) <= 10 { return l }

        let fading = rimStops.joined().contains { $0.isActive(at: clock) } || rimWidth.isActive(at: clock)
        let steady = abs(blob.vh) < 0.05 && abs(blob.vl) < 0.3 && !fading
        // A habit that lasts keeps him moving round his shape at rest (the headphones: height
        // 0.92…1.08, lean ±7): the pictures are drawn for that one, and the stretch and the
        // shear follow the beat
        let swaying = !fading && pose == nil && blob.habit?.lasts == true
        if steady || swaying, !lightQueued, clock - lightBuiltAt > 0.25 {
            lightQueued = true
            let h = steady ? blob.h : 1, lean = steady ? blob.lean : 0
            let rim = f.rim, width = f.rimWidth, scale = displayScale
            let w = max(0.68, min(1.55, 1 / pow(h, 0.62)))
            // Not while the canvas draws: right after
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lightQueued = false
                self.lightBuiltAt = self.clock
                self.light_ = YumiLight.render(h: h, w: w, lean: lean, rim: rim, rimWidth: width, unit: unit, scale: scale)
                self.lightKey = key
                #if DEBUG
                if ProcessInfo.processInfo.environment["YUMI_TRACE_CADENCE"] != nil {
                    fputs(String(format: "YUMI light %.2f s: h %.3f lean %.2f unit %.3f\n", self.clock, h, lean, unit), stderr)
                }
                #endif
            }
        }
        return nil
    }

    // MARK: - Cadence

    /// Asleep for a while, and nobody stirred him: the sleep is deep.
    private var isDeepAsleep: Bool {
        blob.habit == .sleep && pose == nil && clock - max(habitStart, lastStir) > BotEngine.deepSleepAfter
    }

    /// A command arrived: full cadence at once. Called outside of any drawing.
    private func wake(_ why: String = #function) {
        #if DEBUG
        if !isMini, ProcessInfo.processInfo.environment["YUMI_TRACE_CADENCE"] == "2" {
            fputs(String(format: "YUMI wake %.2f s: \(why)\n", clock), stderr)
        }
        #endif
        lastStir = clock
        calmSince = nil
        if cadence != .full { cadence = .full }
    }

    /// What this moment needs.
    private var wantedCadence: YumiCadence {
        let now = clock
        #if DEBUG
        // `YUMI_FREEZE=1` stops the character after 20 s: what the app still costs is not him
        if now > 20, ProcessInfo.processInfo.environment["YUMI_FREEZE"] != nil { return .still }
        #endif
        if pose != nil || scene != nil { return .full }
        // A habit that lasts keeps the body moving, so it is never settled: thirty a second is
        // enough for it, whatever eases meanwhile
        if let habit = blob.habit, habit.lasts { return .habit }
        if blob.habit == .sleep, !isDeepAsleep { return .habit }
        if !blob.isSettled { return .full }
        // A costume lives on its own (a pompom, a glint): thirty a second, like a lasting habit
        if costume.moves, !isMini, !isDeepAsleep { return .habit }

        var easing = [esl, esr, ps, tl, tr, al, ar, bl, br, cl, cr, tilt, lx, ly, eyes,
                      rimWidth, drawn, light, ember, sip, sleepFx]
        easing += rimStops.joined()
        easing += props.values
        if easing.contains(where: { $0.isActive(at: now) }) { return .full }

        // A blink lasts a quarter of a second: full cadence a little before it starts
        let phase = (now + blinkPhase).truncatingRemainder(dividingBy: 5.4)
        if phase > 5.4 * 0.955 - 0.1 { return .full }
        if let b = blinkAt, now - b < 0.3 { return .full }

        // Waiting for an approval, only the glow pulses, over 1.1 s: like a lasting habit, thirty
        // pictures a second look the same. The shake, the blinks, the look and the face still
        // get every frame through the checks above.
        if state == .approval { return .habit }

        if let habit = blob.habit, habit.lasts { return .habit }
        switch blob.habit {
        case .sunglasses:
            // They drop onto his nose in 0.55 s, then nothing moves but his breathing
            return now - habitStart < 0.6 ? .full : .low
        case .sleep:
            // The bubble and the z, until the sleep is deep
            return isDeepAsleep ? .still : .habit
        case .exhausted, nil:
            return .low
        default:
            return .habit
        }
    }

    /// Speeds up at once, slows down only after a short calm, so the cadence does not flap.
    /// Runs while the canvas draws: the change is published right after, not during.
    private func updateCadence() {
        let wanted = wantedCadence
        #if DEBUG
        if !isMini, ProcessInfo.processInfo.environment["YUMI_TRACE_CADENCE"] == "2", Int(clock) != traceSecond {
            traceSecond = Int(clock)
            fputs(String(format: "YUMI wants %.2f s: \(wanted) pose=\(String(describing: pose)) settled=\(blob.isSettled) habit=\(String(describing: blob.habit))\n", clock), stderr)
        }
        #endif
        if wanted == cadence { calmSince = nil; return }
        if wanted < cadence {
            let since = calmSince ?? clock
            calmSince = since
            if clock - since < 0.35 { return }
        }
        guard !cadenceChangeQueued else { return }
        cadenceChangeQueued = true
        let stir = lastStir
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.cadenceChangeQueued = false
            // A command that arrived in between wins
            if wanted < .full, self.lastStir != stir { return }
            self.calmSince = nil
            if self.cadence != wanted { self.cadence = wanted }
        }
    }

    // MARK: - Draw

    /// Points per unit of the mock-up's 100 × 84 box, for a frame of this size. The body is
    /// 84 units wide and takes 68.4 % of the frame width (1.14 × the "diameter" of the layouts).
    static func unit(for frame: CGRect) -> CGFloat { frame.width * 0.684 / 84 }

    /// The room Yumi needs around `frame` so that nothing he does is cut: jumps and stretches
    /// above, the cloud and the notes, droplets and smoke on the sides. In the coordinates of `frame`.
    static func canvasRect(for frame: CGRect, overhang: CGFloat) -> CGRect {
        let u = unit(for: frame)
        let origin = CGPoint(x: frame.midX - 50 * u, y: frame.midY + overhang / 2 - 42 * u)
        return CGRect(x: origin.x - 80 * u, y: origin.y - 70 * u, width: 260 * u, height: 170 * u).union(frame)
    }

    /// Rim width in units of the box, from the scale Yumi is drawn at: the values of `SEATS`
    /// in the mock-up. The smaller he is, the thicker the rim, so that he stays readable at 20 pt.
    private static func rimWidth(atScale s: CGFloat) -> CGFloat {
        let seats: [(CGFloat, CGFloat)] = [(0.05, 6), (0.27, 6.5), (0.42, 4.5), (0.56, 3.4), (0.66, 3), (0.92, 2.8), (1, 2.6)]
        return yumiKeyframes(s, seats, .linear)
    }

    /// The 0.243 s blink of the mock-up, every 5.4 s, or when asked.
    private var blinkValue: CGFloat {
        let p = CGFloat((clock + blinkPhase).truncatingRemainder(dividingBy: 5.4) / 5.4)
        // A mini character only blinks when its view asks (it is not redrawn in between)
        var v = isMini ? 1 : yumiKeyframes(p, [(0, 1), (0.955, 1), (0.975, 0.08), (1, 1)], .ease)
        if let b = blinkAt {
            let q = CGFloat((clock - b) / 0.243)
            if q < 1 { v = min(v, yumiKeyframes(q, [(0, 1), (0.444, 0.08), (1, 1)], .ease)) }
        }
        return v
    }

    /// Draws Yumi for `frame`: the box of the mock-up is centred in it. The context may be
    /// larger than the frame (see `canvasRect(for:overhang:)`).
    #if DEBUG
    private var cpuWindow: (start: Double, cpu: Double, frames: Int)?
    #endif

    func draw(context: GraphicsContext, frame: CGRect) {
        let unit = BotEngine.unit(for: frame)
        #if DEBUG
        // `YUMI_TRACE_CADENCE=4` prints, every 10 s, the CPU of the whole app and the frames drawn
        if !isMini, ProcessInfo.processInfo.environment["YUMI_TRACE_CADENCE"] == "4" {
            let wall = Date().timeIntervalSinceReferenceDate
            let cpu = Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)) / 1e9
            if let w = cpuWindow {
                cpuWindow?.frames += 1
                if wall - w.start >= 10 {
                    fputs(String(format: "YUMI cpu %.1f %% frames/s %.1f unit %.3f\n", (cpu - w.cpu) / (wall - w.start) * 100,
                                 Double(w.frames) / (wall - w.start), unit), stderr)
                    cpuWindow = (wall, cpu, 0)
                }
            } else { cpuWindow = (wall, cpu, 0) }
        }
        #endif
        var ctx = context
        ctx.translateBy(x: frame.midX - 50 * unit, y: frame.midY + particleOverhang / 2 - 42 * unit)
        ctx.scaleBy(x: unit, y: unit)

        if isMini {
            let c = bodyColor.flatMap { $0.components }.flatMap { $0.count >= 3 ? $0 : nil } ?? [1, 1, 1]
            YumiRenderer.drawMini(color: Color(.sRGB, red: Double(c[0]), green: Double(c[1]), blue: Double(c[2])),
                                  blink: blinkValue, asleep: state == .sleeping, in: ctx)
            return
        }

        let width = BotEngine.rimWidth(atScale: unit)
        if rimWidthSet { rimWidth.set(width, at: clock, over: 0.4, .ease) } else { rimWidth.jump(width); rimWidthSet = true }

        let now = clock
        var f = YumiFrame()
        f.h = blob.shapeH
        f.w = blob.shapeW
        f.lean = blob.lean
        f.y = blob.y
        f.air = blob.air
        f.faceShift = CGPoint(x: blob.fx.dx, y: blob.fx.dy)
        f.faceScale = CGSize(width: blob.fx.sx, height: blob.fx.sy)
        f.yaw = blob.yaw
        f.pitch = blob.pitch
        f.face = YumiFace(esl: esl.value(at: now), esr: esr.value(at: now), ps: ps.value(at: now),
                          tl: tl.value(at: now), tr: tr.value(at: now), al: al.value(at: now), ar: ar.value(at: now),
                          bl: bl.value(at: now), br: br.value(at: now), cl: cl.value(at: now), cr: cr.value(at: now),
                          tilt: tilt.value(at: now))
        f.pupil = CGPoint(x: lx.value(at: now), y: ly.value(at: now))
        f.eyesScale = eyes.value(at: now)
        f.blink = blinkValue
        f.rim = rimStops.map { YumiRGB($0[0].value(at: now), $0[1].value(at: now), $0[2].value(at: now)) }
        f.rimWidth = rimWidth.value(at: now)
        f.drawn = drawn.value(at: now)
        f.light = light.value(at: now)
        // Waiting for an approval: the glow pulses
        f.glow = state == .approval
            ? yumiKeyframes(CGFloat(now.truncatingRemainder(dividingBy: 1.1) / 1.1), [(0, 0.85), (0.5, 0.35), (1, 0.85)], .easeInOut)
            : 0.85
        f.props = props.mapValues { $0.value(at: now) }
        f.habitTime = CGFloat(now - habitStart)
        f.emberRadius = ember.value(at: now)
        f.emberHot = blob.drag
        f.sip = sip.value(at: now)
        f.sleepFx = sleepFx.value(at: now)
        if let p = pose {
            if p.showsArms { f.armTime = CGFloat(now - poseStart) }
            if p.showsSparks { f.sparkTime = CGFloat(now - poseStart) }
        }
        f.drops = blob.drops
        f.puffs = blob.puffs
        f.time = CGFloat(now)
        if let s = scene { f.scene = YumiSceneMoment(scene: s.kind, t: CGFloat(now - s.start), amount: s.amount) }
        f.costume = costume
        f.storedLight = storedLight(for: f, unit: unit)
        YumiRenderer.draw(f, in: ctx)
    }
}
