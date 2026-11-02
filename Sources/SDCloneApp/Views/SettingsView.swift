import SwiftUI
import AppKit
import SDCore

/// Impostazioni (⌘,).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("Generali", systemImage: "gearshape") }
            OptimizeSettings().tabItem { Label("Ottimizza", systemImage: "wand.and.stars") }
            AdvancedSettings().tabItem { Label("Avanzate", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.notifyKey) private var notify = true
    @AppStorage(Preferences.soundKey) private var sound = true
    @AppStorage(Preferences.badgeKey) private var dockProgress = true

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Backup") {
                LabeledContent("Cartella dei backup") {
                    HStack(spacing: 8) {
                        Text((model.backupFolder.path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Cambia…") { model.chooseBackupFolder() }
                    }
                }
                Button("Usa la cartella predefinita (Documenti › SDClone)") { model.resetBackupFolder() }
                    .disabled(model.backupFolder == BackupLibrary.defaultDirectory())
                Picker("Formato dei nuovi backup", selection: $model.compressBackups) {
                    Text("Compresso (.img.xz)").tag(true)
                    Text("Non compresso (.img)").tag(false)
                }
            }
            Section("A lavoro finito") {
                Toggle("Mostra una notifica se SD Clone non è in primo piano", isOn: $notify)
                Toggle("Suona un avviso", isOn: $sound)
                Toggle("Mostra l'avanzamento sull'icona nel Dock", isOn: $dockProgress)
            }
        }
        .formStyle(.grouped)
        .disabled(model.hasRunningJob)
    }
}

private struct OptimizeSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Operazioni proposte") {
                Toggle("Riduci al minimo", isOn: $model.optimizeOptions.shrink)
                Toggle("Togli le cronologie", isOn: $model.optimizeOptions.clean)
                Toggle("Comprimi in .xz", isOn: $model.optimizeOptions.compress)
                Toggle("Conserva anche l'immagine non compressa", isOn: $model.optimizeOptions.keepUncompressed)
                    .disabled(!model.optimizeOptions.compress)
            }
            Section("Strumenti e2fsprogs") {
                if let tools = model.e2fsTools {
                    LabeledContent("Trovati in") {
                        Text(tools.directory.path).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                } else {
                    LabeledContent("Stato") {
                        Label("Non installati", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    Text("Servono per Riduci e Togli le cronologie. Installali dal Terminale con  brew install e2fsprogs")
                        .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Button("Ricontrolla") { model.refreshTools() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedSettings: View {
    @AppStorage("disclaimer.acceptedRevision") private var acceptedRevision = 0
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("Avvertenze") {
                LabeledContent("Stato") {
                    Text(acceptedRevision >= Legal.disclaimerRevision ? "Accettate" : "Da accettare")
                        .foregroundStyle(.secondary)
                }
                Button("Mostrale di nuovo al prossimo avvio") { acceptedRevision = 0 }
                    .disabled(acceptedRevision == 0)
            }
            Section("Ripristino delle impostazioni") {
                Button("Ripristina tutte le impostazioni…", role: .destructive) { confirmReset = true }
                Text("Riporta cartella, formato, opzioni di Ottimizza e avvisi ai valori iniziali. Le immagini salvate non vengono toccate.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Informazioni") {
                LabeledContent("Versione", value: "\(AppInfo.version) (\(AppInfo.build))")
                LabeledContent("Comando da terminale") {
                    Text(HelpContent.cliPath).foregroundStyle(.secondary).textSelection(.enabled)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Ripristinare tutte le impostazioni?", isPresented: $confirmReset) {
            Button("Ripristina", role: .destructive) { resetAll() }
        } message: {
            Text("Le avvertenze dovranno essere accettate di nuovo al prossimo avvio.")
        }
    }

    private func resetAll() {
        if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
        let model = AppModel.shared
        model.resetBackupFolder()
        model.compressBackups = true
        model.optimizeOptions = .init(shrink: true, clean: true, compress: true, keepUncompressed: false)
        acceptedRevision = 0
    }
}
