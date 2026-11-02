import SwiftUI

/// Andamento della velocita' di trasferimento, con area sfumata sotto la linea.
struct Sparkline: View {
    let values: [Double]
    var accent: Accent

    var body: some View {
        GeometryReader { geo in
            let smooth = Self.smoothed(values)
            let top = max(smooth.max() ?? 1, 1) * 1.15
            let pts = smooth.enumerated().map { i, v in
                CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(max(smooth.count - 1, 1)),
                        y: geo.size.height * (1 - CGFloat(v / top)))
            }
            ZStack {
                if pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [accent.start.opacity(0.35), accent.end.opacity(0.0)],
                                         startPoint: .top, endPoint: .bottom))

                    Path { p in
                        p.move(to: pts[0])
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(accent.gradient, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                } else {
                    Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
    }

    /// Media mobile corta, per una linea morbida.
    static func smoothed(_ v: [Double], window: Int = 4) -> [Double] {
        guard v.count > 1 else { return v }
        return v.indices.map { i in
            let lo = max(0, i - window + 1)
            let slice = v[lo...i]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }
}
