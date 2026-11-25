import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PosterArtwork: View {
    let art: PosterArt

    var body: some View {
        ZStack {
            background
            if art.isBook {
                bookDecoration
            } else {
                Canvas { context, size in
                    drawMovieArt(art, context: &context, size: size)
                }
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        switch art {
        case .war:
            LinearGradient(colors: [Color(hex: 0x6E1E1A), Color(hex: 0x3B1210), Color(hex: 0x140606)], startPoint: .top, endPoint: .bottom)
        case .stage:
            LinearGradient(colors: [Color(hex: 0x4A0F12), Color(hex: 0x1C0908)], startPoint: .top, endPoint: .bottom)
        case .space:
            LinearGradient(colors: [Color(hex: 0x0E1B2E), Color(hex: 0x16324F), Color(hex: 0x07101C)], startPoint: .top, endPoint: .bottom)
        case .road:
            LinearGradient(colors: [Color(hex: 0x7A2A1A), Color(hex: 0xA34A25), Color(hex: 0x3A1108), Color(hex: 0x120403)], startPoint: .top, endPoint: .bottom)
        case .dunes:
            LinearGradient(colors: [Color(hex: 0x3E2E12), Color(hex: 0x1C1307), Color(hex: 0x0B0703)], startPoint: .top, endPoint: .bottom)
        case .mountains:
            LinearGradient(colors: [Color(hex: 0x233A2E), Color(hex: 0x11221A), Color(hex: 0x07120C)], startPoint: .top, endPoint: .bottom)
        case .sea:
            LinearGradient(colors: [Color(hex: 0x0F2A3A), Color(hex: 0x081A26), Color(hex: 0x04101A)], startPoint: .top, endPoint: .bottom)
        case .bokeh:
            LinearGradient(colors: [Color(hex: 0x0E1B2A), Color(hex: 0x0A1420), Color(hex: 0x050B12)], startPoint: .top, endPoint: .bottom)
        case .forest:
            LinearGradient(colors: [Color(hex: 0x1B3A2A), Color(hex: 0x0F241B), Color(hex: 0x07130E)], startPoint: .top, endPoint: .bottom)
        case .city:
            LinearGradient(colors: [Color(hex: 0x15303A), Color(hex: 0x0D2026), Color(hex: 0x071216)], startPoint: .top, endPoint: .bottom)
        case .nebula:
            LinearGradient(colors: [Color(hex: 0x2A1B3D), Color(hex: 0x1A1026), Color(hex: 0x0C0714)], startPoint: .top, endPoint: .bottom)
        case .anime:
            LinearGradient(colors: [Color(hex: 0x123047), Color(hex: 0x1B4B63), Color(hex: 0x07131C)], startPoint: .top, endPoint: .bottom)
        case .volcano:
            LinearGradient(colors: [Color(hex: 0x2A0D08), Color(hex: 0x160604)], startPoint: .top, endPoint: .bottom)
        case .bookCream:
            LinearGradient(colors: [Color(hex: 0xF8F0DF), Color(hex: 0xEDDCBA), Color(hex: 0xE3CEA4)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .bookViolet:
            RadialGradient(colors: [Color(hex: 0x463358), Color(hex: 0x2A2038), Color(hex: 0x191122)], center: .init(x: 0.5, y: 0.24), startRadius: 0, endRadius: 170)
        case .bookSand:
            LinearGradient(colors: [Color(hex: 0xEEDDBE), Color(hex: 0xDDBF8C), Color(hex: 0xC9A66C)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .bookIvory:
            LinearGradient(colors: [Color(hex: 0xF0EBDD), Color(hex: 0xE2DAC8), Color(hex: 0xCEC4AF)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .bookCharcoal:
            LinearGradient(colors: [Color(hex: 0x2E2A22), Color(hex: 0x1F1C16), Color(hex: 0x14110C)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .bookSage:
            LinearGradient(colors: [Color(hex: 0xD6DFCB), Color(hex: 0xBFCDB4), Color(hex: 0xA7B99E)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .bookTeal:
            LinearGradient(colors: [Color(hex: 0x173F49), Color(hex: 0x0E2D36), Color(hex: 0x071B22)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    @ViewBuilder
    private var bookDecoration: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                LinearGradient(
                    colors: [.black.opacity(0.17), .clear, .clear, .black.opacity(0.11)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(titleColor.opacity(0.22), lineWidth: 1)
                    .padding(6)
                Canvas { context, size in
                    drawBookDecoration(art, context: &context, size: size)
                }
                LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .top, endPoint: .center)
                LinearGradient(colors: [.clear, .black.opacity(0.18)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 1)
                    .padding(.leading, 10)
                    .padding(.vertical, 12)
            }
            .frame(width: w, height: h)
        }
    }

    private var titleColor: Color {
        switch art {
        case .bookViolet, .bookCharcoal, .bookTeal: .white
        default: Color(hex: 0x2C2317)
        }
    }

    private func drawMovieArt(_ art: PosterArt, context: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
        func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ color: Color) {
            let rect = CGRect(x: w * (x - rx), y: h * (y - ry), width: w * rx * 2, height: h * ry * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
        func path(_ color: Color, _ build: (inout Path) -> Void) {
            var p = Path()
            build(&p)
            context.fill(p, with: .color(color))
        }
        func line(_ from: CGPoint, _ to: CGPoint, _ color: Color, width: CGFloat = 1) {
            var p = Path()
            p.move(to: from)
            p.addLine(to: to)
            context.stroke(p, with: .color(color), lineWidth: width)
        }
        func star(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
            ellipse(x, y, r / w, r / h, .white.opacity(0.85))
        }

        switch art {
        case .war:
            ellipse(0.70, 0.34, 0.20, 0.135, Color(hex: 0xFFD9A0).opacity(0.12))
            ellipse(0.70, 0.34, 0.10, 0.068, Color(hex: 0xFFE3B4).opacity(0.92))
            for i in 0..<3 {
                line(point(0.0, 0.18 + CGFloat(i) * 0.09), point(1.0, 0.48 + CGFloat(i) * 0.09), Color(hex: 0xFFD9A0).opacity(0.14), width: 0.7)
            }
            path(Color(hex: 0x30100F).opacity(0.7)) { p in
                p.move(to: point(0, 0.70)); p.addLine(to: point(0.16, 0.63)); p.addLine(to: point(0.30, 0.68)); p.addLine(to: point(0.46, 0.60)); p.addLine(to: point(0.62, 0.65)); p.addLine(to: point(0.78, 0.61)); p.addLine(to: point(1, 0.64)); p.addLine(to: point(1, 1)); p.addLine(to: point(0, 1)); p.closeSubpath()
            }
            path(Color(hex: 0x140505)) { p in
                p.move(to: point(0, 0.81)); p.addLine(to: point(0.22, 0.75)); p.addLine(to: point(0.42, 0.79)); p.addLine(to: point(0.60, 0.73)); p.addLine(to: point(0.82, 0.78)); p.addLine(to: point(1, 0.75)); p.addLine(to: point(1, 1)); p.addLine(to: point(0, 1)); p.closeSubpath()
            }
            for i in 0..<4 {
                let x = 0.16 + CGFloat(i) * 0.07
                ellipse(x, 0.72, 0.012, 0.008, Color(hex: 0x0C0404))
                line(point(x, 0.73), point(x, 0.88), Color(hex: 0x0C0404), width: 1.5)
                line(point(x, 0.77), point(x - 0.035, 0.68), Color(hex: 0x0C0404), width: 0.9)
            }
            path(Color(hex: 0xFFD9A0).opacity(0.12)) { p in
                p.move(to: point(0.48, 0.72)); p.addCurve(to: point(0.57, 0.36), control1: point(0.44, 0.63), control2: point(0.60, 0.50))
            }
        case .stage:
            path(Color(hex: 0x4C1014)) { p in
                p.move(to: .zero); p.addLine(to: point(0.19, 0)); p.addCurve(to: point(0.23, 1), control1: point(0.20, 0.34), control2: point(0.17, 0.7)); p.addLine(to: point(0, 1)); p.closeSubpath()
            }
            path(Color(hex: 0x4C1014)) { p in
                p.move(to: point(1, 0)); p.addLine(to: point(0.81, 0)); p.addCurve(to: point(0.77, 1), control1: point(0.80, 0.34), control2: point(0.83, 0.7)); p.addLine(to: point(1, 1)); p.closeSubpath()
            }
            ellipse(0.50, 0.43, 0.28, 0.20, Color(hex: 0xFFDFA8).opacity(0.13))
            ellipse(0.50, 0.66, 0.36, 0.075, Color(hex: 0xE8B65C).opacity(0.15))
            ellipse(0.50, 0.49, 0.068, 0.068, Color(hex: 0x0B0505))
            path(Color(hex: 0x0B0505)) { p in
                p.move(to: point(0.40, 0.60)); p.addCurve(to: point(0.60, 0.60), control1: point(0.43, 0.52), control2: point(0.57, 0.52)); p.addLine(to: point(0.64, 0.80)); p.addLine(to: point(0.36, 0.80)); p.closeSubpath()
            }
            line(point(0.44, 0.46), point(0.56, 0.46), Color(hex: 0xFFDFA8).opacity(0.45), width: 0.8)
        case .space:
            ellipse(0.66, 0.30, 0.26, 0.17, Color(hex: 0x76A9D6).opacity(0.16))
            ellipse(0.66, 0.30, 0.18, 0.12, Color(hex: 0x8AB8E0))
            ellipse(0.60, 0.25, 0.12, 0.08, Color(hex: 0x6E9BC4).opacity(0.4))
            context.stroke(
                Path(ellipseIn: CGRect(x: w * 0.42, y: h * 0.24, width: w * 0.46, height: h * 0.14)),
                with: .color(Color(hex: 0xF0D9A8).opacity(0.7)),
                lineWidth: 0.8
            )
            for s in [(0.24, 0.13), (0.36, 0.22), (0.16, 0.32), (0.82, 0.15), (0.90, 0.40), (0.44, 0.10), (0.72, 0.52)] {
                star(CGFloat(s.0), CGFloat(s.1), 1.2)
            }
            path(Color(hex: 0x0A1522).opacity(0.85)) { p in
                p.move(to: point(0, 0.80)); p.addQuadCurve(to: point(1, 0.78), control: point(0.5, 0.72)); p.addLine(to: point(1, 1)); p.addLine(to: point(0, 1)); p.closeSubpath()
            }
            path(Color(hex: 0x050B12)) { p in
                p.move(to: point(0, 0.89)); p.addQuadCurve(to: point(1, 0.90), control: point(0.55, 0.85)); p.addLine(to: point(1, 1)); p.addLine(to: point(0, 1)); p.closeSubpath()
            }
        case .road:
            ellipse(0.70, 0.26, 0.13, 0.085, Color(hex: 0xF3C27C).opacity(0.8))
            path(Color(hex: 0x33120F)) { p in
                p.move(to: point(0, 0.72)); p.addLine(to: point(0.2, 0.65)); p.addLine(to: point(0.38, 0.72)); p.addLine(to: point(0.56, 0.64)); p.addLine(to: point(0.76, 0.70)); p.addLine(to: point(1, 0.64)); p.addLine(to: point(1, 1)); p.addLine(to: point(0, 1)); p.closeSubpath()
            }
            path(Color(hex: 0x150606)) { p in
                p.move(to: point(0, 0.84)); p.addLine(to: point(0.30, 0.79)); p.addLine(to: point(0.60, 0.84)); p.addLine(to: point(1, 0.78)); p.addLine(to: point(1, 1)); p.addLine(to: point(0, 1)); p.closeSubpath()
            }
            path(Color(hex: 0x090303)) { p in
                p.move(to: point(0.42, 1)); p.addLine(to: point(0.50, 0.75)); p.addLine(to: point(0.58, 1)); p.closeSubpath()
            }
            path(Color(hex: 0x090303)) { p in
                p.addRect(CGRect(x: w * 0.24, y: h * 0.74, width: w * 0.18, height: h * 0.055))
                p.addRect(CGRect(x: w * 0.28, y: h * 0.70, width: w * 0.12, height: h * 0.045))
            }
            let carY = h * 0.79
            context.fill(Path(ellipseIn: CGRect(x: w * 0.27, y: carY, width: w * 0.045, height: w * 0.045)), with: .color(Color(hex: 0x090303)))
            context.fill(Path(ellipseIn: CGRect(x: w * 0.42, y: carY, width: w * 0.045, height: w * 0.045)), with: .color(Color(hex: 0x090303)))
            line(point(0.50, 0.78), point(0.18, 1), Color(hex: 0xF3C27C).opacity(0.18), width: 0.8)
            line(point(0.50, 0.78), point(0.82, 1), Color(hex: 0xF3C27C).opacity(0.18), width: 0.8)
        case .dunes:
            ellipse(0.50, 0.33, 0.20, 0.135, Color(hex: 0xF2DDB0).opacity(0.12))
            ellipse(0.50, 0.33, 0.105, 0.07, Color(hex: 0xF2DDB0).opacity(0.35))
            path(Color(hex: 0x5A4322).opacity(0.8)) { p in
                p.move(to: point(0, 0.72)); p.addCurve(to: point(0.58, 0.72), control1: point(0.24, 0.58), control2: point(0.44, 0.58)); p.addCurve(to: point(1, 0.68), control1: point(0.78, 0.78), control2: point(0.9, 0.66)); p.addLine(to: point(1, 1)); p.addLine(to: point(0, 1)); p.closeSubpath()
            }
            path(Color(hex: 0x1A1208)) { p in
                p.move(to: point(0, 0.85)); p.addCurve(to: point(0.62, 0.84), control1: point(0.26, 0.76), control2: point(0.44, 0.9)); p.addCurve(to: point(1, 0.9), control1: point(0.78, 0.82), control2: point(0.9, 0.85)); p.addLine(to: point(1, 1)); p.addLine(to: point(0, 1)); p.closeSubpath()
            }
            path(Color(hex: 0x1A1208)) { p in
                p.addRect(CGRect(x: w * 0.64, y: h * 0.64, width: w * 0.035, height: h * 0.05))
                p.addRect(CGRect(x: w * 0.77, y: h * 0.61, width: w * 0.022, height: h * 0.04))
            }
        case .mountains:
            ellipse(0.68, 0.23, 0.075, 0.05, Color(hex: 0xCFE8D8).opacity(0.7))
            path(Color(hex: 0x1B3A31).opacity(0.78)) { p in
                p.move(to: point(0, 0.64)); p.addLine(to: point(0.18, 0.48)); p.addLine(to: point(0.34, 0.59)); p.addLine(to: point(0.50, 0.40)); p.addLine(to: point(0.68, 0.56)); p.addLine(to: point(0.84, 0.47)); p.addLine(to: point(1, 0.61)); p.addLine(to: point(1, 1)); p.addLine(to: point(0, 1)); p.closeSubpath()
            }
            path(Color(hex: 0x0E241E).opacity(0.92)) { p in
                p.move(to: point(0, 0.76)); p.addLine(to: point(0.22, 0.61)); p.addLine(to: point(0.40, 0.72)); p.addLine(to: point(0.58, 0.59)); p.addLine(to: point(0.76, 0.71)); p.addLine(to: point(0.92, 0.64)); p.addLine(to: point(1, 0.69)); p.addLine(to: point(1, 1)); p.addLine(to: point(0, 1)); p.closeSubpath()
            }
            path(Color(hex: 0x071410)) { p in
                p.move(to: point(0, 0.88)); p.addQuadCurve(to: point(1, 0.88), control: point(0.5, 0.82)); p.addLine(to: point(1, 1)); p.addLine(to: point(0, 1)); p.closeSubpath()
            }
            for i in 0..<3 {
                let x = 0.20 + CGFloat(i) * 0.17
                line(point(x, 0.98), point(x + 0.13, 0.72), Color(hex: 0xD9EDE2).opacity(0.16), width: 0.8)
            }
            path(Color(hex: 0x071410)) { p in
                p.addRect(CGRect(x: w * 0.14, y: h * 0.84, width: w * 0.035, height: h * 0.07))
                p.addRect(CGRect(x: w * 0.20, y: h * 0.82, width: w * 0.018, height: h * 0.09))
            }
        case .sea:
            ellipse(0.72, 0.23, 0.13, 0.085, Color(hex: 0xF6E2B8).opacity(0.12))
            ellipse(0.72, 0.23, 0.075, 0.05, Color(hex: 0xF6E2B8).opacity(0.85))
            path(Color(hex: 0x0A2230)) { p in
                p.addRect(CGRect(x: 0, y: h * 0.64, width: w, height: h * 0.36))
            }
            for i in 0..<5 {
                let y = h * (0.72 + CGFloat(i) * 0.045)
                var p = Path(); p.move(to: point(0.08, 0.72 + CGFloat(i) * 0.045)); p.addLine(to: point(0.30, 0.72 + CGFloat(i) * 0.045))
                context.stroke(p, with: .color(Color(hex: 0xF6E2B8).opacity(0.22)), lineWidth: 0.8)
                _ = y
            }
            path(Color(hex: 0x08131A)) { p in
                p.move(to: point(0.20, 0.61)); p.addLine(to: point(0.56, 0.61)); p.addLine(to: point(0.51, 0.67)); p.addLine(to: point(0.25, 0.67)); p.closeSubpath()
                p.addRect(CGRect(x: w * 0.28, y: h * 0.55, width: w * 0.18, height: h * 0.06))
                p.addRect(CGRect(x: w * 0.36, y: h * 0.47, width: w * 0.018, height: h * 0.09))
            }
            for i in 0..<6 {
                let x = 0.08 + CGFloat(i) * 0.10
                path(Color(hex: 0xF6E2B8).opacity(0.78)) { p in
                    p.addRect(CGRect(x: w * x, y: h * 0.92, width: w * 0.075, height: h * 0.028))
                }
            }
        case .bokeh:
            path(Color(hex: 0xF0D9B5).opacity(0.10)) { p in
                p.addRect(CGRect(x: w * 0.12, y: h * 0.11, width: w * 0.76, height: h * 0.64))
            }
            ellipse(0.26, 0.19, 0.09, 0.06, Color(hex: 0xF6E3C8).opacity(0.75))
            ellipse(0.64, 0.15, 0.06, 0.04, Color(hex: 0xF6E3C8).opacity(0.6))
            ellipse(0.78, 0.31, 0.09, 0.06, Color(hex: 0xF6E3C8).opacity(0.7))
            ellipse(0.38, 0.37, 0.05, 0.034, Color(hex: 0xF6E3C8).opacity(0.55))
            for s in [(0.18, 0.78), (0.30, 0.69), (0.46, 0.81), (0.62, 0.72), (0.78, 0.84), (0.86, 0.65)] {
                star(CGFloat(s.0), CGFloat(s.1), 1.1)
            }
            ellipse(0.42, 0.78, 0.055, 0.037, Color(hex: 0x050B12))
            ellipse(0.58, 0.79, 0.05, 0.034, Color(hex: 0x050B12))
        case .forest:
            ellipse(0.50, 0.25, 0.12, 0.08, Color(hex: 0xE9F2C8).opacity(0.35))
            path(Color(hex: 0x12301F).opacity(0.7)) { p in
                p.addRect(CGRect(x: w * 0.10, y: h * 0.33, width: w * 0.08, height: h * 0.68))
                p.addRect(CGRect(x: w * 0.76, y: h * 0.28, width: w * 0.10, height: h * 0.73))
            }
            path(Color(hex: 0x1C4430).opacity(0.82)) { p in
                p.addRect(CGRect(x: w * 0.30, y: h * 0.47, width: w * 0.06, height: h * 0.54))
                p.addRect(CGRect(x: w * 0.58, y: h * 0.40, width: w * 0.07, height: h * 0.61))
            }
            path(Color(hex: 0x0A1F16)) { p in
                p.move(to: point(0, 0.85)); p.addQuadCurve(to: point(1, 0.85), control: point(0.5, 0.78)); p.addLine(to: point(1, 1)); p.addLine(to: point(0, 1)); p.closeSubpath()
            }
            for s in [(0.40, 0.0, 0.20, 1.0), (0.60, 0.0, 0.76, 1.0)] {
                line(point(CGFloat(s.0), CGFloat(s.1)), point(CGFloat(s.2), CGFloat(s.3)), Color(hex: 0xDCEBB8).opacity(0.13), width: 2)
            }
        case .city:
            ellipse(0.76, 0.20, 0.055, 0.036, Color(hex: 0xE9D6A8).opacity(0.7))
            let buildings: [(CGFloat, CGFloat, CGFloat)] = [(0.0, 0.57, 0.14), (0.18, 0.48, 0.12), (0.34, 0.63, 0.16), (0.54, 0.43, 0.12), (0.70, 0.55, 0.14), (0.88, 0.47, 0.12)]
            for b in buildings {
                path(Color(hex: 0x0A1519)) { p in
                    p.addRect(CGRect(x: w * b.0, y: h * b.1, width: w * b.2, height: h * (1 - b.1)))
                }
            }
            for b in buildings {
                for row in 0..<3 {
                    let x = b.0 + 0.03 + CGFloat(row) * 0.035
                    path(Color(hex: 0xF0D9A8).opacity(0.5)) { p in
                        p.addRect(CGRect(x: w * x, y: h * (b.1 + 0.05 + CGFloat(row) * 0.08), width: w * 0.012, height: w * 0.025))
                    }
                }
            }
            path(Color(hex: 0x050A0C)) { p in
                p.addRect(CGRect(x: 0, y: h * 0.93, width: w, height: h * 0.07))
            }
            line(point(0, 0.93), point(0.5, 0.80), Color(hex: 0xE9D6A8).opacity(0.18), width: 0.8)
            line(point(0.5, 0.80), point(1, 0.93), Color(hex: 0xE9D6A8).opacity(0.18), width: 0.8)
        case .nebula:
            ellipse(0.60, 0.36, 0.26, 0.17, Color(hex: 0xB07AD6).opacity(0.2))
            ellipse(0.60, 0.36, 0.14, 0.09, Color(hex: 0xE4B6FF).opacity(0.3))
            context.stroke(Path(ellipseIn: CGRect(x: w * 0.35, y: h * 0.29, width: w * 0.50, height: h * 0.14)), with: .color(Color(hex: 0xE4B6FF).opacity(0.45)), lineWidth: 0.9)
            context.stroke(Path(ellipseIn: CGRect(x: w * 0.43, y: h * 0.20, width: w * 0.34, height: h * 0.32)), with: .color(Color(hex: 0x8FD6E8).opacity(0.3)), lineWidth: 0.7)
            for s in [(0.24, 0.13), (0.42, 0.09), (0.82, 0.16), (0.90, 0.40), (0.18, 0.41), (0.70, 0.56)] {
                star(CGFloat(s.0), CGFloat(s.1), 1.2)
            }
            path(Color(hex: 0x0B0812)) { p in
                p.move(to: point(0, 0.84)); p.addQuadCurve(to: point(1, 0.84), control: point(0.5, 0.78)); p.addLine(to: point(1, 1)); p.addLine(to: point(0, 1)); p.closeSubpath()
            }
        case .anime:
            ellipse(0.76, 0.20, 0.12, 0.08, Color(hex: 0xFFE6A8).opacity(0.8))
            ellipse(0.30, 0.29, 0.18, 0.047, Color(hex: 0xEAF6FF).opacity(0.5))
            ellipse(0.22, 0.27, 0.10, 0.033, Color(hex: 0xEAF6FF).opacity(0.45))
            ellipse(0.66, 0.40, 0.14, 0.034, Color(hex: 0xEAF6FF).opacity(0.45))
            path(Color(hex: 0x0B1B2A)) { p in
                p.move(to: point(0, 0.84)); p.addQuadCurve(to: point(1, 0.84), control: point(0.5, 0.77)); p.addLine(to: point(1, 1)); p.addLine(to: point(0, 1)); p.closeSubpath()
            }
            path(Color(hex: 0x0B1B2A)) { p in
                p.addRoundedRect(in: CGRect(x: w * 0.34, y: h * 0.61, width: w * 0.14, height: h * 0.14), cornerSize: CGSize(width: 2, height: 2))
                p.addRoundedRect(in: CGRect(x: w * 0.37, y: h * 0.56, width: w * 0.08, height: h * 0.06), cornerSize: CGSize(width: 2, height: 2))
            }
            ellipse(0.41, 0.68, 0.012, 0.008, Color(hex: 0x8FD6E8))
            line(point(0.30, 0.64), point(0.22, 0.59), Color(hex: 0x0B1B2A), width: 2)
            line(point(0.48, 0.64), point(0.56, 0.59), Color(hex: 0x0B1B2A), width: 2)
            line(point(0.36, 0.75), point(0.36, 0.83), Color(hex: 0x0B1B2A), width: 2)
            line(point(0.43, 0.75), point(0.43, 0.83), Color(hex: 0x0B1B2A), width: 2)
        case .volcano:
            ellipse(0.50, 0.80, 0.30, 0.10, Color(hex: 0xFF8A4C).opacity(0.25))
            path(Color(hex: 0x1A0D09)) { p in
                p.move(to: point(0, 0.79)); p.addLine(to: point(0.20, 0.57)); p.addLine(to: point(0.38, 0.69)); p.addLine(to: point(0.52, 0.49)); p.addLine(to: point(0.70, 0.67)); p.addLine(to: point(0.84, 0.56)); p.addLine(to: point(1, 0.75)); p.addLine(to: point(1, 1)); p.addLine(to: point(0, 1)); p.closeSubpath()
            }
            path(Color(hex: 0xF06A33).opacity(0.65)) { p in
                p.move(to: point(0.52, 0.49)); p.addLine(to: point(0.62, 0.75)); p.addLine(to: point(0.42, 0.75)); p.closeSubpath()
            }
            path(Color(hex: 0xE8B65C).opacity(0.25)) { p in
                p.move(to: point(0.52, 0.49)); p.addCurve(to: point(0.54, 0.23), control1: point(0.48, 0.40), control2: point(0.58, 0.32))
            }
            path(Color(hex: 0x0A0503)) { p in
                p.addRect(CGRect(x: 0, y: h * 0.89, width: w, height: h * 0.11))
            }
        case .bookCream, .bookViolet, .bookSand, .bookIvory, .bookCharcoal, .bookSage, .bookTeal:
            break
        }
    }

    private func drawBookDecoration(_ art: PosterArt, context: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ color: Color) {
            context.fill(Path(ellipseIn: CGRect(x: w * (x - rx), y: h * (y - ry), width: w * rx * 2, height: h * ry * 2)), with: .color(color))
        }
        switch art {
        case .bookCream:
            for i in 0..<20 {
                var p = Path()
                p.move(to: CGPoint(x: w * 0.08, y: h * 0.10 + CGFloat(i) * h * 0.04))
                p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.10 + CGFloat(i) * h * 0.04))
                context.stroke(p, with: .color(Color(hex: 0x5A401E).opacity(0.045)), lineWidth: 0.6)
            }
            ellipse(0.50, 0.27, 0.20, 0.14, .white.opacity(0.20))
        case .bookViolet:
            for (x, y) in [(0.30, 0.22), (0.62, 0.17), (0.76, 0.34), (0.44, 0.42)] {
                ellipse(CGFloat(x), CGFloat(y), 0.006, 0.004, .white.opacity(0.75))
            }
            var p = Path()
            p.move(to: CGPoint(x: w * 0.30, y: h * 0.22)); p.addLine(to: CGPoint(x: w * 0.62, y: h * 0.17))
            p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.34))
            context.stroke(p, with: .color(.white.opacity(0.22)), lineWidth: 0.8)
        case .bookSand:
            var p = Path()
            p.move(to: CGPoint(x: w * 0.55, y: h * 0.10)); p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.72))
            context.stroke(p, with: .color(Color(hex: 0x7A5A2C).opacity(0.18)), lineWidth: 1)
        case .bookIvory:
            ellipse(0.50, 0.31, 0.09, 0.065, Color(hex: 0x3C5044).opacity(0.18))
            var p = Path()
            p.move(to: CGPoint(x: w * 0.10, y: h * 0.18)); p.addLine(to: CGPoint(x: w * 0.84, y: h * 0.76))
            context.stroke(p, with: .color(Color(hex: 0x3C5044).opacity(0.14)), lineWidth: 0.9)
        case .bookCharcoal:
            ellipse(0.74, 0.20, 0.13, 0.085, Color(hex: 0xE8BC6A).opacity(0.24))
        case .bookSage:
            var p = Path()
            p.move(to: CGPoint(x: w * 0.24, y: h * 0.14)); p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.72))
            context.stroke(p, with: .color(Color(hex: 0x253020).opacity(0.16)), lineWidth: 1)
        case .bookTeal:
            for i in 0..<4 {
                var p = Path()
                p.move(to: CGPoint(x: w * 0.10, y: h * (0.18 + CGFloat(i) * 0.08)))
                p.addQuadCurve(to: CGPoint(x: w * 0.90, y: h * (0.18 + CGFloat(i) * 0.08)), control: CGPoint(x: w * 0.50, y: h * (0.12 + CGFloat(i) * 0.08)))
                context.stroke(p, with: .color(Color(hex: 0x8FD6C4).opacity(0.2)), lineWidth: 0.8)
            }
        default:
            break
        }
    }
}

struct CoverArtwork: View {
    @Environment(\.isEnabled) private var isEnabled
    let art: PosterArt
    var urlString: String?
    var localKey: String?
    #if canImport(UIKit)
    @State private var remoteImage: UIImage?
    #endif

    private var loadToken: String {
        let version = localKey.map { CoverStore.version(for: $0) } ?? "0"
        return "\(resolvedURL ?? "")|\(localKey ?? "")|\(version)|\(isEnabled)"
    }

    private var resolvedURL: String? {
        guard let value = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return value
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PosterArtwork(art: art)
                #if canImport(UIKit)
                if let remoteImage {
                    Image(uiImage: remoteImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
                #endif
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .task(id: loadToken) {
            guard isEnabled else { return }
            #if canImport(UIKit)
            if let localKey {
                let cacheKey = "local:\(localKey)"
                if let cached = CoverImageCache.cached(cacheKey) {
                    remoteImage = cached
                    return
                }
                let local = await Task.detached(priority: .utility) {
                    CoverStore.cachedImage(for: localKey)
                }.value
                guard !Task.isCancelled else { return }
                if let local {
                    CoverImageCache.put(local, for: cacheKey)
                    remoteImage = local
                } else {
                    remoteImage = nil
                }
                return
            }
            guard let resolvedURL else {
                remoteImage = nil
                return
            }
            if let cached = CoverImageCache.cached(resolvedURL) {
                remoteImage = cached
                return
            }
            remoteImage = await CoverImageCache.load(resolvedURL)
            #endif
        }
    }
}

#if canImport(UIKit)
@MainActor
private enum CoverImageCache {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 80 * 1024 * 1024
        return cache
    }()

    static func cached(_ key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    static func put(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height * 4))
    }

    static func load(_ value: String) async -> UIImage? {
        if let cached = cached(value) { return cached }
        for candidate in mirrorURLs(value) {
            guard !Task.isCancelled, let url = URL(string: candidate) else { return nil }
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("https://movie.douban.com/", forHTTPHeaderField: "Referer")
            request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                let image = await Task.detached(priority: .utility) {
                    UIImage(data: data)
                }.value
                guard let image else { continue }
                cache.setObject(image, forKey: value as NSString, cost: data.count)
                return image
            } catch {
                continue
            }
        }
        return nil
    }

    private static func mirrorURLs(_ value: String) -> [String] {
        guard var components = URLComponents(string: value) else { return [value] }
        let hosts = ["img3.doubanio.com", "img1.doubanio.com", "img2.doubanio.com", "img9.doubanio.com"]
        var result = [value]
        for host in hosts where host != components.host {
            components.host = host
            if let candidate = components.string, !result.contains(candidate) {
                result.append(candidate)
            }
        }
        return result
    }
}
#endif

struct PosterCover: View {
    let record: MediaRecord

    var body: some View {
        ZStack {
            CoverArtwork(art: record.art, urlString: record.coverRemoteURL, localKey: record.coverLocalKey)
            if !record.usesBuiltinCover {
                LinearGradient(
                    colors: [.clear, .clear, .black.opacity(0.28)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [.clear, .clear, .black.opacity(record.art.isBook ? 0.05 : 0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if record.art.isBook {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(titleColor)
                            .opacity(0.35)
                            .frame(width: 20, height: 1)
                            .padding(.bottom, 8)
                        Text(record.title)
                            .font(.appSerifTitle)
                            .foregroundStyle(titleColor)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 8)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 18)
                    .padding(.horizontal, 8)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Spacer(minLength: 0)
                        Text(record.title)
                            .font(.system(size: record.art == .war || record.art == .stage || record.art == .dunes ? 14 : 12.5, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .shadow(color: .black.opacity(0.35), radius: 4)
                        if let year = record.year {
                            Text(year)
                                .font(.system(size: 5.5, weight: .medium))
                                .tracking(1.2)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .padding(8)
                }
            }

            VStack {
                HStack {
                    if record.isWish {
                        Text(record.statusLabel)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.38))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    Spacer()
                    if record.rating > 0 {
                        Text("\(record.rating).0")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(hex: 0x241804))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Theme.goldBright)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                Spacer()
            }
            .padding(6)
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.white.opacity(record.art.isBook ? 0.4 : 0.12), lineWidth: 1)
        )
    }

    private var titleColor: Color {
        switch record.art {
        case .bookViolet, .bookCharcoal, .bookTeal: .white.opacity(0.92)
        default: Color(hex: 0x2C2317)
        }
    }
}

struct PosterCardView: View {
    let record: MediaRecord
    var onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button(action: onTap) {
                PosterCover(record: record)
            }
            .buttonStyle(.plain)

            Text(record.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .truncationMode(.tail)
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            Text(record.statsText)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text3)
                .lineLimit(1)

            if record.mediaType == .movie {
                Text(record.isWish ? L10n.Records.markedOn(record.displayMarkedDate) : record.displayDate)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.text4)
                    .lineLimit(1)
            }

        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
