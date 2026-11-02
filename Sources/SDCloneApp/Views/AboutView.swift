import SwiftUI
import AppKit

/// Finestra "Informazioni su SD Clone".
struct AboutView: View {
    @Environment(\.openWindow) private var openWindow
    @AppStorage("legal.tab") private var legalTab = LegalView.Tab.disclaimer.rawValue

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(nsImage: AppInfo.icon)
                    .resizable()
                    .frame(width: 112, height: 112)
                    .shadow(color: Accent.backup.start.opacity(0.35), radius: 18, y: 8)
                VStack(spacing: 4) {
                    Text(AppInfo.name).font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Versione \(AppInfo.version) (\(AppInfo.build))")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text(AppInfo.tagline)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300)
            }
            .padding(.top, 34)

            VStack(spacing: 3) {
                Text("Ideato e sviluppato da").font(.caption).foregroundStyle(.secondary)
                Text(AppInfo.author).font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .padding(.top, 20)

            HStack(spacing: 8) {
                Badge(symbol: "gift.fill", text: "Gratuito")
                Badge(symbol: "hand.raised.fill", text: "Nessun dato raccolto")
                Badge(symbol: "lock.shield.fill", text: "Dischi del Mac protetti")
            }
            .padding(.top, 18)

            Spacer(minLength: 18)

            HStack(spacing: 10) {
                Button("Pagina del progetto") { NSWorkspace.shared.open(AppInfo.projectURL) }
                Button("Avvertenze") { open(.disclaimer) }
                Button("Licenza MIT") { open(.license) }
                Button("Terze parti") { open(.thirdParty) }
            }
            .buttonStyle(.secondaryAction)
            .fixedSize()

            Text(AppInfo.copyright + ". Licenza MIT. Software fornito «così com'è», senza garanzie.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
                .padding(.bottom, 18)
        }
        .padding(.horizontal, 28)
        .frame(width: 560, height: 520)
        .background(AppBackground(accent: .backup))
    }

    private func open(_ tab: LegalView.Tab) {
        legalTab = tab.rawValue
        openWindow(id: "legal")
    }

    private struct Badge: View {
        let symbol: String
        let text: String

        var body: some View {
            Label(text, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
                .fixedSize()
        }
    }
}
