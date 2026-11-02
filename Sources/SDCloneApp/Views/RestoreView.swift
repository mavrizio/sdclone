import SwiftUI
import SDCore
import UniformTypeIdentifiers

struct RestoreView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Scrolling {
            VStack(alignment: .leading, spacing: 26) {
                ScreenHeader(title: Mode.restore.title, subtitle: Mode.restore.subtitle)

                VStack(alignment: .leading, spacing: 14) {
                    StepHeader(number: 1, title: "Scegli l'immagine")
                    ImageDropZone(selection: $model.restoreImage, choose: model.chooseRestoreImage)
                }

                VStack(alignment: .leading, spacing: 14) {
                    StepHeader(number: 2, title: "Scegli la scheda da scrivere")
                    DiskPicker(requireFit: model.restoreImage.flatMap { model.imageSize($0) })
                }

                if let problem = model.restoreProblem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 14) {
                    Button { model.showRestoreConfirm = true } label: {
                        Label("Ripristina…", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.primaryAction)
                    .disabled(!model.canStartRestore)
                    .keyboardShortcut(.defaultAction)

                    Label("Il contenuto della scheda verrà cancellato. Prima ti chiederò conferma.",
                          systemImage: "exclamationmark.shield.fill")
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
        .sheet(isPresented: $model.showRestoreConfirm) {
            ConfirmRestoreSheet()
        }
    }
}

/// Scelta di un'immagine: trascinamento, pannello o uno dei backup recenti. Usata da Ripristina e Ottimizza.
struct ImageDropZone: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent
    @Binding var selection: URL?
    let choose: () -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 14) {
            if let url = selection {
                chosen(url)
            } else {
                empty
            }

            let recent = Array(model.library.prefix(4))
            if !recent.isEmpty {
                HStack(spacing: 8) {
                    Text("Recenti").font(.caption).foregroundStyle(.secondary)
                    ForEach(recent) { entry in
                        Button { selection = entry.url } label: {
                            Text(entry.name).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(Capsule().fill(selection == entry.url ? AnyShapeStyle(accent.gradient.opacity(0.25)) : AnyShapeStyle(Color.primary.opacity(0.07))))
                        .overlay(Capsule().strokeBorder(selection == entry.url ? accent.start.opacity(0.6) : .clear, lineWidth: 1))
                    }
                    Spacer()
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { ["img", "xz"].contains($0.pathExtension.lowercased()) }) else { return false }
            selection = url
            return true
        } isTargeted: { targeted = $0 }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 34))
                .foregroundStyle(accent.gradient)
                .scaleEffect(targeted ? 1.2 : 1)
            Text("Trascina qui un file .img o .img.xz").font(.system(size: 17, weight: .semibold, design: .rounded))
            Text("oppure sceglilo dal Mac o dall'Archivio").font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Scegli file…") { choose() }.buttonStyle(.secondaryAction)
                Button("Apri l'Archivio") { model.mode = .library }.buttonStyle(.secondaryAction)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(targeted ? accent.start.opacity(0.12) : Color.clear))
        .card(cornerRadius: 24, padding: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(accent.start.opacity(targeted ? 0.9 : 0.35), style: StrokeStyle(lineWidth: 1.8, dash: [8, 6]))
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: targeted)
    }

    private func chosen(_ url: URL) -> some View {
        let entry = model.library.first { $0.url == url }
        let size = model.imageSize(url)
        return HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent.gradient)
                    .frame(width: 54, height: 54)
                Image(systemName: "opticaldiscdrive.fill").font(.system(size: 24)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(url.lastPathComponent).font(.system(size: 16, weight: .semibold, design: .rounded)).lineLimit(1)
                    if url.lastPathComponent.lowercased().hasSuffix(".xz") { Pill(text: "XZ", tint: accent.start) }
                }
                HStack(spacing: 10) {
                    if let size { Text(url.lastPathComponent.lowercased().hasSuffix(".xz") ? "immagine da \(ByteFormat.string(size))" : ByteFormat.string(size)) }
                    if let entry { Text(entry.date, style: .date) }
                    if (entry?.sha256 ?? BackupLibrary.sha256(forImage: url)) != nil {
                        Label("SHA256 noto", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    }
                }
                .font(.callout).foregroundStyle(.secondary)
                Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Cambia…") { choose() }.buttonStyle(.secondaryAction)
            Button { selection = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.secondaryAction)
        }
        .card(cornerRadius: 22, padding: 18)
    }
}

/// Ultima barriera prima di scrivere: mostra cosa verra' cancellato e chiede di digitare il nome del disco.
struct ConfirmRestoreSheet: View {
    @Environment(AppModel.self) private var model
    @State private var typed = ""
    @FocusState private var focused: Bool

    var body: some View {
        let accent = Accent.restore
        VStack(spacing: 22) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(accent.gradient)
                .shadow(color: accent.start.opacity(0.5), radius: 14)

            if let disk = model.selectedDisk, let image = model.restoreImage {
                let p = DiskInfoPresentation(disk: disk)
                VStack(spacing: 6) {
                    Text("Cancellare «\(p.title)»?")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Tutto il contenuto della scheda \(disk.identifier) (\(p.sizeLabel)) verrà sostituito da\n«\(image.lastPathComponent)». Non si può annullare.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }

                HStack(spacing: 22) {
                    SDCardView(width: 56, label: p.shortSize, caption: "SD", style: p.cardStyle)
                    Image(systemName: "arrow.left").font(.title2).foregroundStyle(.secondary)
                    Image(systemName: "opticaldiscdrive.fill").font(.system(size: 36)).foregroundStyle(accent.gradient)
                }

                VStack(spacing: 8) {
                    Text("Per confermare scrivi  **\(disk.identifier)**").font(.callout)
                    TextField(disk.identifier, text: $typed)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .padding(.vertical, 10)
                        .frame(width: 220)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.07)))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(typed == disk.identifier ? Color.green : Color.primary.opacity(0.15), lineWidth: 1.5))
                        .focused($focused)
                }

                HStack(spacing: 12) {
                    Button("Annulla") { model.showRestoreConfirm = false }
                        .buttonStyle(.secondaryAction)
                        .keyboardShortcut(.cancelAction)
                    Button { model.startRestore() } label: {
                        Label("Cancella e ripristina", systemImage: "flame.fill")
                    }
                    .buttonStyle(.primaryAction)
                    .environment(\.accent, accent)
                    .disabled(typed.trimmingCharacters(in: .whitespaces) != disk.identifier)
                }
            }
        }
        .padding(34)
        .frame(width: 480)
        .onAppear { focused = true }
    }
}
