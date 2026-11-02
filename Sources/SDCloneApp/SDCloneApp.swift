import SwiftUI
import AppKit

@main
struct SDCloneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        Window("SD Clone", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1080, height: 760)
        .commands { AppCommands(model: model) }

        Window("Informazioni su SD Clone", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Guida di SD Clone", id: "help") {
            HelpView()
        }
        .defaultSize(width: 900, height: 640)

        Window("Avvertenze", id: "legal") {
            LegalView()
        }
        .defaultSize(width: 680, height: 640)

        Settings {
            SettingsView().environment(model)
        }
    }
}

/// Menu dell'app: Informazioni, File, Vai e Aiuto.
struct AppCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("Informazioni su SD Clone") { openWindow(id: "about") }
        }

        CommandGroup(replacing: .newItem) {
            Button("Apri immagine da ripristinare…") {
                guard model.job == nil else { return }
                model.mode = .restore
                model.chooseRestoreImage()
            }
            .keyboardShortcut("o")
            Button("Apri immagine da ottimizzare…") {
                guard model.job == nil else { return }
                model.mode = .optimize
                model.chooseOptimizeImage()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Mostra la cartella dei backup") { model.showBackupFolder() }
                .keyboardShortcut("b", modifiers: [.command, .option])
        }

        CommandMenu("Vai") {
            ForEach(Array(Mode.allCases.enumerated()), id: \.element) { i, mode in
                Button(mode.sidebarTitle) { if model.job == nil { model.mode = mode } }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
            }
            Divider()
            Button("Espelli la scheda selezionata") {
                if let disk = model.selectedDisk { model.eject(disk) }
            }
            .keyboardShortcut("e")
        }

        CommandGroup(replacing: .help) {
            Button("Guida di SD Clone") { openWindow(id: "help") }
                .keyboardShortcut("?")
            Divider()
            Button("Avvertenze e responsabilità") { openLegal(.disclaimer) }
            Button("Licenza") { openLegal(.license) }
            Button("Privacy") { openLegal(.privacy) }
            Button("Componenti di terze parti") { openLegal(.thirdParty) }
            Divider()
            Button("Pagina del progetto") { NSWorkspace.shared.open(AppInfo.projectURL) }
            Button("Segnala un problema…") { NSWorkspace.shared.open(AppInfo.issuesURL) }
        }
    }

    private func openLegal(_ tab: LegalView.Tab) {
        UserDefaults.standard.set(tab.rawValue, forKey: "legal.tab")
        openWindow(id: "legal")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Serve anche quando l'eseguibile parte fuori da un pacchetto .app (swift run).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Snapshot.scheduleIfRequested()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Immagini aperte dal Finder ("Apri con", trascinate sull'icona nel Dock).
    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { ["img", "xz"].contains($0.pathExtension.lowercased()) }) else { return }
        AppModel.shared.openImage(url)
    }

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = AppModel.shared
        guard model.hasRunningJob, model.job?.waitingForAuthorization == false else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Un'operazione è ancora in corso"
        alert.informativeText = "Se esci adesso verrà annullata" + (model.job?.kind == .restore
            ? " e la scheda potrebbe restare incompleta." : ".")
        alert.addButton(withTitle: "Continua")
        alert.addButton(withTitle: "Annulla ed esci")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }

        // L'helper gira come root e controlla il file di annullamento a ogni blocco: gli si da' il tempo di fermarsi.
        model.cancelJob()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
