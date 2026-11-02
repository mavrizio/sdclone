import SwiftUI
import SDCore

struct BackupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Scrolling {
            VStack(alignment: .leading, spacing: 26) {
                ScreenHeader(title: Mode.backup.title, subtitle: Mode.backup.subtitle)

                VStack(alignment: .leading, spacing: 14) {
                    StepHeader(number: 1, title: "Scegli la scheda",
                               detail: model.disks.isEmpty ? nil : "\(model.disks.count) rilevat\(model.disks.count == 1 ? "a" : "e")")
                    DiskPicker()
                }

                VStack(alignment: .leading, spacing: 14) {
                    StepHeader(number: 2, title: "Dove salvarla")
                    DestinationCard()
                }

                HStack(spacing: 14) {
                    Button { model.startBackup() } label: {
                        Label("Avvia il backup", systemImage: "play.fill")
                    }
                    .buttonStyle(.primaryAction)
                    .disabled(!model.canStartBackup)
                    .keyboardShortcut(.defaultAction)

                    Label("Ti verrà chiesta la password di amministratore.", systemImage: "lock.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .padding(.bottom, 36)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct DestinationCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(accent.gradient)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cartella").font(.caption).foregroundStyle(.secondary)
                    Text(abbreviated(model.backupFolder))
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Menu {
                    ForEach(Array(model.quickFolders.enumerated()), id: \.offset) { _, folder in
                        Button(folder.title) { model.useFolder(folder.url) }
                    }
                } label: {
                    Label("Vai a", systemImage: "arrowshape.turn.up.right.fill")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule(style: .continuous).fill(.regularMaterial))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Documenti, Scrivania e cartelle di Google Drive")
                Button("Cambia…") { model.chooseBackupFolder() }
                    .buttonStyle(.secondaryAction)
            }

            Divider().opacity(0.5)

            HStack(spacing: 14) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(accent.gradient)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Formato").font(.caption).foregroundStyle(.secondary)
                    Picker("Formato", selection: $model.compressBackups) {
                        Text("Immagine  .img").tag(false)
                        Text("Compressa  .img.xz").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 380)
                    Text(model.compressBackups
                         ? "Di solito da 3 a 5 volte più piccola: ideale da caricare su Google Drive. Impiega qualche minuto in più."
                         : "File identico alla scheda, pronto da usare ovunque. Occupa più spazio.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider().opacity(0.5)

            HStack(spacing: 14) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(accent.gradient)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nome del file").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 2) {
                        TextField("Nome", text: Binding(get: { model.backupName },
                                                        set: { model.backupName = $0; model.nameEdited = true }))
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .medium))
                        Text(model.compressBackups ? ".img.xz" : ".img").foregroundStyle(.secondary).font(.system(size: 14))
                    }
                }
            }

            Divider().opacity(0.5)

            SummaryLine()
        }
        .card(cornerRadius: 22, padding: 20)
    }

    private func abbreviated(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}

private struct SummaryLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            if let disk = model.selectedDisk {
                let used = disk.estimatedUsedBytes
                Image(systemName: model.backupFitsOnDisk ? "info.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.backupFitsOnDisk ? Color.secondary : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Group {
                        if model.compressBackups {
                            Text("Verranno copiati circa **\(ByteFormat.string(used))** su \(ByteFormat.string(disk.sizeBytes)): la copia si ferma alla fine dell'ultima partizione, e il file finale sarà di circa **\(ByteFormat.string(used / 5)) – \(ByteFormat.string(used / 3))**.")
                        } else {
                            Text("Verranno copiati circa **\(ByteFormat.string(used))** su \(ByteFormat.string(disk.sizeBytes)): la copia si ferma alla fine dell'ultima partizione, così il file non occupa spazio inutile.")
                        }
                    }
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    if let free = model.freeSpace {
                        Text(model.backupFitsOnDisk
                             ? "Spazio libero sul Mac: \(ByteFormat.string(free))."
                             : "Spazio insufficiente: sul Mac restano solo \(ByteFormat.string(free)). Scegli un'altra cartella.")
                            .font(.callout)
                            .foregroundStyle(model.backupFitsOnDisk ? Color.secondary : Color.orange)
                    }
                }
            } else {
                Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
                Text("Scegli una scheda per vedere quanto spazio serve.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
