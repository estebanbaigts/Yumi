import SwiftUI

// What he holds while an agent works, besides the cigarette, the coffee and the matcha
// (YumiWorkHabit): a mug of tea, a bottle of water, a glass of juice, a book, a gamepad, a
// knitting. Drawn in the space of the props of YumiRenderer (a 100 × 84 box, the face round
// 50, 45); the cups sit by his right side like the coffee and turn with the face, the rest is
// held low in front of him and stays with the body.

extension YumiRenderer {

    /// `face` turns with the head (YumiFaceTurn), `held` does not.
    static func drawWorkProps(_ f: YumiFrame, face: GraphicsContext, held: GraphicsContext) {
        if let o = f.props[.tea], o > 0.01 { drawTea(f, o, face) }
        if let o = f.props[.water], o > 0.01 { drawWater(f, o, face) }
        if let o = f.props[.juice], o > 0.01 { drawJuice(f, o, face) }
        if let o = f.props[.book], o > 0.01 { drawBook(f, o, held) }
        if let o = f.props[.gamepad], o > 0.01 { drawGamepad(f, o, held) }
        if let o = f.props[.knitting], o > 0.01 { drawKnitting(f, o, held) }
        // .focus: empty hands, nothing to draw
    }

    /// A cup tips towards the mouth for a sip, around (`x`, `y`).
    private static func tipped(_ f: YumiFrame, _ o: CGFloat, _ props: GraphicsContext,
                               x: CGFloat, y: CGFloat, angle: Double) -> GraphicsContext {
        var c = props
        c.opacity = o
        c.translateBy(x: 8, y: 8)
        c.translateBy(x: x, y: y)
        c.rotate(by: .degrees(angle * Double(f.sip)))
        c.translateBy(x: -3 * f.sip, y: -3 * f.sip)
        c.translateBy(x: -x, y: -y)
        return c
    }

    private static func drawTea(_ f: YumiFrame, _ o: CGFloat, _ props: GraphicsContext) {
        let c = tipped(f, o, props, x: 66, y: 60, angle: -26)
        // A tall mug in a soft sage
        let mug = Color(.sRGB, red: 0.776, green: 0.851, blue: 0.784)
        c.fill(Path(roundedRect: CGRect(x: 65, y: 52.5, width: 12, height: 13), cornerRadius: 2.4), with: .color(mug))
        var handle = Path()
        handle.move(to: CGPoint(x: 77, y: 55.5))
        handle.addQuadCurve(to: CGPoint(x: 77, y: 62), control: CGPoint(x: 82.5, y: 58.8))
        c.stroke(handle, with: .color(mug), lineWidth: 1.8)
        c.fill(Path(ellipseIn: CGRect(x: 65.6, y: 52, width: 10.8, height: 2.2)), with: .color(Color(.sRGB, red: 0.651, green: 0.420, blue: 0.220)))
        // The string of the tea bag over the rim, and its little paper label
        c.stroke(line(CGPoint(x: 67.5, y: 53), CGPoint(x: 64.2, y: 58.8)), with: .color(.white.opacity(0.85)), lineWidth: 0.5)
        let swing = 1.2 * sin(f.time * 1.7)
        c.fill(Path(roundedRect: CGRect(x: 61.6 + swing * 0.3, y: 58.4, width: 4.2, height: 4.6), cornerRadius: 0.6),
               with: .color(Color(.sRGB, red: 0.957, green: 0.639, blue: 0.247)))
    }

    private static func drawWater(_ f: YumiFrame, _ o: CGFloat, _ props: GraphicsContext) {
        let c = tipped(f, o, props, x: 70, y: 58, angle: -38)
        // A clear bottle with a blue cap; the water inside sways
        let glass = Color(.sRGB, red: 0.780, green: 0.886, blue: 0.957)
        c.fill(Path(roundedRect: CGRect(x: 66.5, y: 50, width: 9, height: 17), cornerRadius: 3), with: .color(glass.opacity(0.75)))
        let level = 57 + 0.8 * sin(f.time * 2.4)
        c.fill(Path(roundedRect: CGRect(x: 67.3, y: level, width: 7.4, height: 66.2 - level), cornerRadius: 2.4),
               with: .color(Color(.sRGB, red: 0.420, green: 0.686, blue: 0.957).opacity(0.8)))
        c.fill(Path(roundedRect: CGRect(x: 68.2, y: 46.8, width: 5.6, height: 3.6), cornerRadius: 1), with: .color(Color(.sRGB, red: 0.231, green: 0.459, blue: 0.886)))
        c.stroke(line(CGPoint(x: 68.4, y: 52.5), CGPoint(x: 68.4, y: 63)), with: .color(.white.opacity(0.5)), style: round(0.9))
    }

    private static func drawJuice(_ f: YumiFrame, _ o: CGFloat, _ props: GraphicsContext) {
        let c = tipped(f, o, props, x: 68, y: 60, angle: -12)
        // A glass of orange juice, a slice on the rim, a striped straw that leans to his mouth
        var glass = Path()
        glass.move(to: CGPoint(x: 65, y: 52))
        glass.addLine(to: CGPoint(x: 77, y: 52))
        glass.addLine(to: CGPoint(x: 75.6, y: 66))
        glass.addLine(to: CGPoint(x: 66.4, y: 66))
        glass.closeSubpath()
        c.fill(glass, with: .color(Color.white.opacity(0.35)))
        var juice = Path()
        juice.move(to: CGPoint(x: 65.6, y: 55.5))
        juice.addLine(to: CGPoint(x: 76.4, y: 55.5))
        juice.addLine(to: CGPoint(x: 75.5, y: 65.4))
        juice.addLine(to: CGPoint(x: 66.5, y: 65.4))
        juice.closeSubpath()
        c.fill(juice, with: .color(Color(.sRGB, red: 1, green: 0.651, blue: 0.180)))
        // The straw: drawn in two colours, dashed
        let straw = line(CGPoint(x: 72, y: 62), CGPoint(x: 64 - 3 * f.sip, y: 45 + 2 * f.sip))
        c.stroke(straw, with: .color(.white), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        c.stroke(straw, with: .color(Color(.sRGB, red: 0.937, green: 0.267, blue: 0.369)),
                 style: StrokeStyle(lineWidth: 1.6, lineCap: .butt, dash: [1.6, 1.6]))
        var slice = Path()
        slice.addArc(center: CGPoint(x: 77, y: 52.4), radius: 3, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: true)
        slice.closeSubpath()
        c.fill(slice, with: .color(Color(.sRGB, red: 0.988, green: 0.808, blue: 0.341)))
    }

    private static func drawBook(_ f: YumiFrame, _ o: CGFloat, _ props: GraphicsContext) {
        var c = props
        c.opacity = o
        // Held up in front of him, above the bottom of the body
        c.translateBy(x: 0, y: -7)
        // An open book held in front of him, the cover in his accent of blue
        let cover = Color(.sRGB, red: 0.247, green: 0.373, blue: 0.659)
        c.fill(Path(roundedRect: CGRect(x: 33, y: 60, width: 34, height: 15), cornerRadius: 1.6), with: .color(cover))
        let paper = Color(.sRGB, red: 0.976, green: 0.961, blue: 0.918)
        var left = Path()
        left.move(to: CGPoint(x: 34.5, y: 61))
        left.addQuadCurve(to: CGPoint(x: 50, y: 62.4), control: CGPoint(x: 42, y: 59.4))
        left.addLine(to: CGPoint(x: 50, y: 74))
        left.addQuadCurve(to: CGPoint(x: 34.5, y: 73.4), control: CGPoint(x: 42, y: 72))
        left.closeSubpath()
        var right = left.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 100, ty: 0))
        c.fill(left, with: .color(paper))
        c.fill(right, with: .color(paper))
        // Lines of text
        for i in 0..<4 {
            let y = 64.5 + CGFloat(i) * 2.4
            c.stroke(line(CGPoint(x: 37, y: y), CGPoint(x: 47.5, y: y + 0.3)), with: .color(.black.opacity(0.18)), lineWidth: 0.6)
            c.stroke(line(CGPoint(x: 52.5, y: y + 0.3), CGPoint(x: 63, y: y)), with: .color(.black.opacity(0.18)), lineWidth: 0.6)
        }
        // Every five seconds a page turns, from right to left
        let p = (f.habitTime / 5).truncatingRemainder(dividingBy: 1)
        if p > 0.84 {
            let k = (p - 0.84) / 0.16
            right = right.applying(CGAffineTransform(translationX: -50, y: 0)
                .scaledBy(x: 1, y: 1)
                .concatenating(CGAffineTransform(a: cos(k * .pi), b: 0, c: 0, d: 1, tx: 50, ty: 0)))
            c.fill(right, with: .color(Color(.sRGB, red: 0.933, green: 0.914, blue: 0.863)))
        }
        c.stroke(line(CGPoint(x: 50, y: 62.3), CGPoint(x: 50, y: 74)), with: .color(.black.opacity(0.2)), lineWidth: 0.6)
    }

    private static func drawGamepad(_ f: YumiFrame, _ o: CGFloat, _ props: GraphicsContext) {
        var c = props
        c.opacity = o
        // Held up in front of him, above the bottom of the body
        c.translateBy(x: 0, y: -7)
        let t = f.time
        c.translateBy(x: 0, y: 0.6 * sin(t * 9))
        // A rounded controller with two grips
        var pad = Path()
        pad.addRoundedRect(in: CGRect(x: 35, y: 61, width: 30, height: 10), cornerSize: CGSize(width: 5, height: 5))
        pad.addEllipse(in: CGRect(x: 33, y: 63, width: 10, height: 11))
        pad.addEllipse(in: CGRect(x: 57, y: 63, width: 10, height: 11))
        c.fill(pad, with: .color(Color(.sRGB, red: 0.200, green: 0.212, blue: 0.247)))
        // The cross on the left, the four buttons on the right
        let light = GraphicsContext.Shading.color(Color(.sRGB, red: 0.565, green: 0.580, blue: 0.627))
        c.fill(Path(CGRect(x: 39.2, y: 65.2, width: 5.6, height: 1.6)), with: light)
        c.fill(Path(CGRect(x: 41.2, y: 63.2, width: 1.6, height: 5.6)), with: light)
        let colours: [Color] = [YumiRGB(hex: 0xFF5D6C).color, YumiRGB(hex: 0x3DDC97).color, YumiRGB(hex: 0x5B8CFF).color, YumiRGB(hex: 0xFFB547).color]
        for (i, d) in [(0.0, -1.9), (1.9, 0.0), (0.0, 1.9), (-1.9, 0.0)].enumerated() {
            c.fill(circle(58 + d.0, 66 + d.1, 0.9), with: .color(colours[i]))
        }
        // The thumbs: two small blobs of his colour pressing the buttons in turn
        let thumb = GraphicsContext.Shading.color(f.rim[0].color.opacity(0.95))
        let l = CGPoint(x: 42 + 1.2 * sin(t * 7), y: 65.8 + 0.9 * cos(t * 5))
        let presses = Int(t * 3.2) % 4
        let r = [(0.0, -1.9), (1.9, 0.0), (0.0, 1.9), (-1.9, 0.0)][presses]
        c.fill(circle(l.x, l.y, 2.2), with: thumb)
        c.fill(circle(58 + r.0, 66 + r.1 - 0.4, 2.1), with: thumb)
    }

    private static func drawKnitting(_ f: YumiFrame, _ o: CGFloat, _ props: GraphicsContext) {
        var c = props
        c.opacity = o
        // Held up in front of him, above the bottom of the body
        c.translateBy(x: 0, y: -7)
        let t = f.time
        let wool = Color(.sRGB, red: 0.961, green: 0.541, blue: 0.851)
        // The knitted piece hanging from the needles, which grows as the session lasts
        let rows = min(9, 3 + f.habitTime / 20)
        c.fill(Path(roundedRect: CGRect(x: 42, y: 63, width: 16, height: rows), cornerRadius: 1.4), with: .color(wool))
        for i in 0..<Int(rows / 1.8) {
            let y = 64.2 + CGFloat(i) * 1.8
            c.stroke(line(CGPoint(x: 43, y: y), CGPoint(x: 57, y: y)), with: .color(.white.opacity(0.22)), lineWidth: 0.5)
        }
        // Two needles that cross and part with each stitch
        let k = sin(t * 5.2)
        let needle = GraphicsContext.Shading.color(Color(.sRGB, red: 0.851, green: 0.725, blue: 0.537))
        c.stroke(line(CGPoint(x: 34, y: 58 + 1.5 * k), CGPoint(x: 55 + 2 * k, y: 64)), with: needle, style: round(1.2))
        c.stroke(line(CGPoint(x: 66, y: 58 - 1.5 * k), CGPoint(x: 45 - 2 * k, y: 64)), with: needle, style: round(1.2))
        c.fill(circle(34, 58 + 1.5 * k, 1.1), with: needle)
        c.fill(circle(66, 58 - 1.5 * k, 1.1), with: needle)
        // The yarn ball beside him, which grows as he winds the wool back
        let ball = min(6, 3.4 + f.habitTime / 40)
        c.fill(circle(73, 72 - ball, ball), with: .color(wool))
        c.stroke(Path(ellipseIn: CGRect(x: 73 - ball * 0.8, y: 72 - ball * 1.6, width: ball * 1.6, height: ball * 0.9)),
                 with: .color(.white.opacity(0.3)), lineWidth: 0.5)
        var yarn = Path()
        yarn.move(to: CGPoint(x: 70, y: 70 - ball))
        yarn.addQuadCurve(to: CGPoint(x: 57, y: 64), control: CGPoint(x: 64, y: 74))
        c.stroke(yarn, with: .color(wool), lineWidth: 0.6)
    }
}
