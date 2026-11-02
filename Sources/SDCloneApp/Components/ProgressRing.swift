import SwiftUI

/// Anello di avanzamento con sfumatura angolare, punta luminosa e alone.
struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 22
    var accent: Accent
    /// Senza una percentuale nota l'anello gira su se stesso.
    var indeterminate = false

    @State private var spin = false

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = (size - lineWidth) / 2
            let f = indeterminate ? 0.28 : max(0.001, min(fraction, 1))

            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)

                // alone
                Circle()
                    .trim(from: 0, to: f)
                    .stroke(accent.start.opacity(0.55), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .blur(radius: 14)
                    .rotationEffect(.degrees(-90))

                Circle()
                    .trim(from: 0, to: f)
                    .stroke(AngularGradient(colors: [accent.start, accent.end],
                                            center: .center, startAngle: .degrees(0),
                                            endAngle: .degrees(max(40, 360 * f))),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                // punta luminosa
                if !indeterminate && f > 0.01 {
                    Circle()
                        .fill(.white.opacity(0.9))
                        .frame(width: lineWidth * 0.32, height: lineWidth * 0.32)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(360 * f))
                        .blur(radius: 0.5)
                }
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(indeterminate && spin ? 360 : 0))
            .animation(indeterminate ? .linear(duration: 1.4).repeatForever(autoreverses: false) : .easeOut(duration: 0.35),
                       value: indeterminate ? spin : false)
            .animation(.easeOut(duration: 0.35), value: fraction)
            .onAppear { spin = true }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.midY + rect.height * 0.02))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY - rect.height * 0.22))
        p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.minY + rect.height * 0.22))
        return p
    }
}

struct CrossShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.22))
        p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.maxY - rect.height * 0.22))
        p.move(to: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.minY + rect.height * 0.22))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.maxY - rect.height * 0.22))
        return p
    }
}

/// Esito finale: anello pieno con segno che si disegna da solo.
struct OutcomeBadge: View {
    enum Kind { case success, failure, cancelled }
    let kind: Kind
    var size: CGFloat = 200

    @State private var drawn = false

    private var accent: Accent {
        switch kind {
        case .success: return .success
        case .failure: return .failure
        case .cancelled: return .neutral
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(accent.start.opacity(0.18)).blur(radius: 24).scaleEffect(1.1)
            Circle().stroke(accent.gradient, lineWidth: size * 0.07)
            (kind == .success ? AnyShape(CheckmarkShape()) : AnyShape(CrossShape()))
            .trim(from: 0, to: drawn ? 1 : 0)
            .stroke(accent.gradient, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round, lineJoin: .round))
            .padding(size * 0.2)
        }
        .frame(width: size, height: size)
        .scaleEffect(drawn ? 1 : 0.8)
        .opacity(drawn ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) { drawn = true }
        }
    }
}
