import SwiftUI

/// Colore guida di una schermata: sfumatura usata per pulsanti, anelli, selezioni e sfondo.
struct Accent {
    let start: Color
    let end: Color

    var gradient: LinearGradient {
        LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let backup = Accent(start: Color(red: 0.14, green: 0.44, blue: 0.98), end: Color(red: 0.16, green: 0.80, blue: 0.88))
    static let restore = Accent(start: Color(red: 1.00, green: 0.55, blue: 0.16), end: Color(red: 0.96, green: 0.22, blue: 0.42))
    static let optimize = Accent(start: Color(red: 0.00, green: 0.62, blue: 0.62), end: Color(red: 0.36, green: 0.84, blue: 0.52))
    static let library = Accent(start: Color(red: 0.56, green: 0.34, blue: 0.96), end: Color(red: 0.30, green: 0.55, blue: 1.00))
    static let success = Accent(start: Color(red: 0.13, green: 0.76, blue: 0.40), end: Color(red: 0.36, green: 0.88, blue: 0.62))
    static let failure = Accent(start: Color(red: 0.96, green: 0.26, blue: 0.30), end: Color(red: 1.00, green: 0.46, blue: 0.36))
    static let neutral = Accent(start: Color(red: 0.50, green: 0.55, blue: 0.64), end: Color(red: 0.68, green: 0.72, blue: 0.80))
}

private struct AccentKey: EnvironmentKey {
    static let defaultValue = Accent.backup
}

extension EnvironmentValues {
    var accent: Accent {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}

enum Mode: String, CaseIterable, Identifiable {
    case backup, optimize, restore, library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backup: return "Salva una SD"
        case .optimize: return "Ottimizza un'immagine"
        case .restore: return "Ripristina"
        case .library: return "Archivio"
        }
    }

    var sidebarTitle: String {
        switch self {
        case .backup: return "Backup"
        case .optimize: return "Ottimizza"
        case .restore: return "Ripristina"
        case .library: return "Archivio"
        }
    }

    var subtitle: String {
        switch self {
        case .backup: return "Crea un'immagine della scheda e controlla che sia integra."
        case .optimize: return "Riduci, ripulisci e comprimi un backup prima di distribuirlo o caricarlo su Drive."
        case .restore: return "Scrivi un'immagine su una scheda e verifica il risultato."
        case .library: return "I backup salvati sul tuo Mac."
        }
    }

    var symbol: String {
        switch self {
        case .backup: return "square.and.arrow.down.fill"
        case .optimize: return "wand.and.stars"
        case .restore: return "arrow.uturn.backward.circle.fill"
        case .library: return "tray.full.fill"
        }
    }

    var accent: Accent {
        switch self {
        case .backup: return .backup
        case .optimize: return .optimize
        case .restore: return .restore
        case .library: return .library
        }
    }
}

// MARK: - Carte

extension View {
    /// Superficie semitrasparente con bordo sottile e ombra morbida.
    func card(cornerRadius: CGFloat = 20, padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.10), radius: 16, y: 8)
    }
}

// MARK: - Pulsanti

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accent) private var accent
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .padding(.vertical, 13)
            .background(
                Capsule(style: .continuous)
                    .fill(isEnabled ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(Color.gray.opacity(0.35)))
                    .overlay(Capsule().fill(.white.opacity(hovering && isEnabled ? 0.14 : 0)))
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: isEnabled ? accent.start.opacity(configuration.isPressed ? 0.25 : 0.45) : .clear,
                    radius: configuration.isPressed ? 6 : 14, y: configuration.isPressed ? 2 : 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule(style: .continuous).fill(.regularMaterial))
            .overlay(Capsule().fill(Color.primary.opacity(hovering ? 0.06 : 0)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primaryAction: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondaryAction: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Piccoli elementi

struct Pill: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

struct StepHeader: View {
    @Environment(\.accent) private var accent
    let number: Int
    let title: String
    var detail: String?

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(accent.gradient))
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Spacer()
            if let detail {
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

struct ScreenHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 32, weight: .bold, design: .rounded))
            Text(subtitle).font(.system(size: 15)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
