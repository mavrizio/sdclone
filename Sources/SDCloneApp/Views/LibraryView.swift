import SwiftUI
import SDCore

struct LibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Scrolling {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeader(title: Mode.library.title, subtitle: Mode.library.subtitle)

                HStack(spacing: 10) {
                    Image(systemName: "folder.fill").foregroundStyle(.secondary)
                    Text((model.backupFolder.path as NSString).abbreviatingWithTildeInPath)
                        .font(.callout).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Apri nel Finder") { model.reveal(model.backupFolder) }.buttonStyle(.secondaryAction)
                }

                if model.library.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 12) {
                        ForEach(model.library) { entry in
                            LibraryRow(entry: entry)
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .padding(.bottom, 36)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .onAppear { model.refreshLibrary() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray").font(.system(size: 38)).foregroundStyle(.secondary)
            Text("Ancora nessun backup").font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("I backup che crei compariranno qui, pronti da ripristinare.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Crea il primo backup") { model.mode = .backup }
                .buttonStyle(.primaryAction)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .card(cornerRadius: 24, padding: 8)
    }
}

private struct LibraryRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent
    let entry: BackupEntry
    @State private var hovering = false
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(accent.gradient).frame(width: 46, height: 46)
                Image(systemName: entry.isCompressed ? "archivebox.fill" : "opticaldiscdrive.fill")
                    .font(.system(size: 20)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entry.name).font(.system(size: 15.5, weight: .semibold, design: .rounded)).lineLimit(1).truncationMode(.middle)
                    if entry.isCompressed { Pill(text: "XZ", tint: accent.start) }
                }
                HStack(spacing: 10) {
                    if entry.isCompressed, let raw = entry.uncompressedBytes {
                        Text("\(ByteFormat.string(entry.sizeBytes)) · immagine da \(ByteFormat.string(raw))")
                    } else {
                        Text(ByteFormat.string(entry.sizeBytes))
                    }
                    Text(entry.date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                    if entry.sha256 != nil {
                        Label("SHA256", systemImage: "checkmark.seal.fill").foregroundStyle(.green).help("Integrità registrata")
                    }
                }
                .font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Button { model.setOptimizeImage(entry.url) } label: { Label("Ottimizza", systemImage: "wand.and.stars") }
                    .buttonStyle(.secondaryAction)
                    .help("Riduci, ripulisci e comprimi questa immagine in un file nuovo.")
                if !entry.isCompressed {
                    Button { model.startCompress(entry) } label: { Label("Comprimi", systemImage: "archivebox") }
                        .buttonStyle(.secondaryAction)
                        .help("Crea un .img.xz molto più piccolo, per caricarlo su Drive. L'originale resta dov'è.")
                }
                Button { model.setRestoreImage(entry.url) } label: {
                    Label("Ripristina", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.secondaryAction)
                Button { model.reveal(entry.url) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.secondaryAction).help("Mostra nel Finder")
                Button { confirmDelete = true } label: { Image(systemName: "trash") }
                    .buttonStyle(.secondaryAction).help("Sposta nel Cestino")
            }
            .fixedSize()
            .opacity(hovering ? 1 : 0.55)
        }
        .card(cornerRadius: 20, padding: 14)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .confirmationDialog("Spostare «\(entry.url.lastPathComponent)» nel Cestino?", isPresented: $confirmDelete) {
            Button("Sposta nel Cestino", role: .destructive) { model.moveToTrash(entry) }
        } message: {
            Text("Il file occupa \(ByteFormat.string(entry.sizeBytes)).")
        }
    }
}
