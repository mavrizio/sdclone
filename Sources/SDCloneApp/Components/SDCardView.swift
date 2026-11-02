import SwiftUI

/// Sagoma di una scheda SD: angolo smussato in alto a destra, contatti in basso.
struct SDCardShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, r = w * 0.07
        var p = Path()
        p.move(to: CGPoint(x: r, y: 0))
        p.addLine(to: CGPoint(x: w * 0.66, y: 0))
        p.addLine(to: CGPoint(x: w, y: w * 0.34))
        p.addLine(to: CGPoint(x: w, y: h - r))
        p.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: r, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: r))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: 0))
        p.closeSubpath()
        return p
    }
}

struct SDCardView: View {
    enum Style {
        case raspberry, graphite, blue

        var colors: [Color] {
            switch self {
            case .raspberry: return [Color(red: 0.86, green: 0.16, blue: 0.34), Color(red: 0.56, green: 0.07, blue: 0.22)]
            case .graphite: return [Color(red: 0.34, green: 0.37, blue: 0.43), Color(red: 0.14, green: 0.16, blue: 0.20)]
            case .blue: return [Color(red: 0.20, green: 0.42, blue: 0.92), Color(red: 0.08, green: 0.16, blue: 0.48)]
            }
        }
    }

    let width: CGFloat
    var label: String
    var caption: String = "SD"
    var style: Style = .graphite

    private var height: CGFloat { width * 1.36 }

    var body: some View {
        let w = width, h = height
        ZStack {
            SDCardShape()
                .fill(LinearGradient(colors: style.colors, startPoint: .topLeading, endPoint: .bottomTrailing))

            // etichetta
            VStack(spacing: w * 0.02) {
                Text(label)
                    .font(.system(size: w * 0.19, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(caption)
                    .font(.system(size: w * 0.09, weight: .semibold, design: .rounded))
                    .opacity(0.6)
            }
            .foregroundStyle(Color(red: 0.12, green: 0.13, blue: 0.18))
            .frame(width: w * 0.72, height: w * 0.44)
            .background(RoundedRectangle(cornerRadius: w * 0.05, style: .continuous).fill(.white.opacity(0.94)))
            .position(x: w * 0.5, y: h * 0.47)

            // contatti dorati
            HStack(spacing: w * 0.022) {
                ForEach(0..<8, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.84, blue: 0.45),
                                                      Color(red: 0.78, green: 0.56, blue: 0.20)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: w * 0.068, height: w * 0.16)
                }
            }
            .position(x: w * 0.5, y: h - w * 0.15)

            // interruttore di protezione
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.black.opacity(0.35))
                .frame(width: w * 0.035, height: w * 0.13)
                .position(x: w * 0.012, y: h * 0.26)

            // riflesso e bordo
            SDCardShape()
                .fill(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.02), .clear],
                                     startPoint: .topLeading, endPoint: .center))
            SDCardShape().stroke(.white.opacity(0.28), lineWidth: 1)
        }
        .frame(width: w, height: h)
        .shadow(color: style.colors[0].opacity(0.40), radius: w * 0.16, y: w * 0.08)
    }
}
