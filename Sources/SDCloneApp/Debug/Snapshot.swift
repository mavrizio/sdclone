import SwiftUI
import AppKit

/// Strumento di sviluppo: `SDCLONE_SNAPSHOT=/percorso/file.png` salva una foto dell'interfaccia dopo
/// `SDCLONE_SNAPSHOT_DELAY` secondi (default 2) ed esce. Con `SDCLONE_DEMO=1` e `SDCLONE_DEMO_STATE`
/// da' screenshot riproducibili, senza permessi di registrazione schermo.
/// `SDCLONE_SCHEME=dark|light` sceglie l'aspetto.
enum Snapshot {
    static let isActive = ProcessInfo.processInfo.environment["SDCLONE_SNAPSHOT"] != nil

    @MainActor
    static func scheduleIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["SDCLONE_SNAPSHOT"] else { return }
        let delay = Double(env["SDCLONE_SNAPSHOT_DELAY"] ?? "") ?? 2
        let scheme: ColorScheme = env["SDCLONE_SCHEME"] == "dark" ? .dark : .light

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let background = scheme == .dark ? Color.black : Color.white
            let renderer: ImageRenderer<AnyView>
            // Fogli e finestre secondarie non si disegnano dentro RootView: si fotografano da soli.
            let single: AnyView? = switch env["SDCLONE_SNAPSHOT_VIEW"] {
            case "confirm": AnyView(ConfirmRestoreSheet())
            case "disclaimer": AnyView(DisclaimerSheet())
            case "about": AnyView(AboutView())
            case "legal": AnyView(LegalView().frame(width: 620, height: 640))
            case "help":
                AnyView(HelpTopicView(topic: HelpContent.topics.first { $0.id == env["SDCLONE_HELP_TOPIC"] } ?? HelpContent.topics[0])
                    .padding(32).frame(width: 700, alignment: .leading))
            default: nil
            }
            if let single {
                renderer = ImageRenderer(content: AnyView(
                    single
                        .environment(AppModel.shared)
                        .environment(\.colorScheme, scheme)
                        .background(background)))
            } else {
                renderer = ImageRenderer(content: AnyView(
                    RootView()
                        .environment(AppModel.shared)
                        .environment(\.colorScheme, scheme)
                        .frame(width: 1080, height: 760)
                        .background(background)))
            }
            renderer.scale = 2
            guard let tiff = renderer.nsImage?.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                FileHandle.standardError.write(Data("snapshot: rendering fallito\n".utf8))
                exit(1)
            }
            do { try png.write(to: URL(fileURLWithPath: path)) } catch {
                FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
                exit(1)
            }
            exit(0)
        }
    }
}
