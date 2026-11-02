import SwiftUI
import AppKit
import SDCore

/// Riduce, ripulisce e comprime un'immagine gia' salvata. Lavora su file nuovi: niente password, niente schede.
struct OptimizeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Scrolling {
            VStack(alignment: .leading, spacing: 26) {
                ScreenHeader(title: Mode.optimize.title, subtitle: Mode.optimize.subtitle)

                VStack(alignment: .leading, spacing: 14) {
                    StepHeader(number: 1, title: "Scegli l'immagine")
                    ImageDropZone(selection: $model.optimizeImage, choose: model.chooseOptimizeImage)
                    if model.optimizeImage != nil { AnalysisCard() }
                }

                VStack(alignment: .leading, spacing: 14) {
                    StepHeader(number: 2, title: "Cosa fare")
                    if model.e2fsTools == nil { MissingToolsCard() }
                    OptionsCard()
                }

                if let problem = model.optimizeProblem, model.optimizeImage != nil {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 14) {
                    Button { model.startOptimize() } label: {
                        Label("Ottimizza", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.primaryAction)
                    .disabled(!model.canStartOptimize)
                    .keyboardShortcut(.defaultAction)

                    Label("L'immagine di partenza non viene modificata: il risultato è un file nuovo.",
                          systemImage: "lock.doc.fill")
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
        .onAppear { model.refreshTools() }
    }
}

// MARK: - Analisi

/// Partizioni dell'immagine e quanto si puo' guadagnare.
private struct AnalysisCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent

    var body: some View {
        Group {
            if let a = model.optimizeAnalysis {
                content(a)
            } else if let error = model.optimizeAnalysisError {
                Label(error, systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Leggo le partizioni…").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .card(cornerRadius: 20, padding: 18)
    }

    private func content(_ a: ImageAnalysis) -> some View {
        let parts = a.partitions.sorted { $0.startSector < $1.startSector }.map {
            PartitionInfo(identifier: "p\($0.number)", name: "", content: $0.diskutilContent, sizeBytes: $0.sizeBytes)
        }
        return VStack(alignment: .leading, spacing: 14) {
            PartitionBar(partitions: parts, total: a.imageBytes, height: 12)
            PartitionLegend(partitions: parts, total: a.imageBytes)
            Divider().opacity(0.5)
            HStack(spacing: 0) {
                Fact(title: "Immagine", value: ByteFormat.string(a.imageBytes))
                Fact(title: "Partizione Linux", value: ByteFormat.string(a.root.sizeBytes))
                if let estimate = a.estimatedShrunkBytes {
                    Fact(title: "Dopo la riduzione", value: "≈ " + ByteFormat.string(estimate), highlight: estimate < a.imageBytes)
                    Fact(title: "Risparmio", value: "≈ " + ByteFormat.string(a.imageBytes - min(estimate, a.imageBytes)),
                         highlight: estimate < a.imageBytes)
                } else if a.isCompressed {
                    Fact(title: "Dopo la riduzione", value: "si vedrà estraendola")
                }
            }
        }
    }

    private struct Fact: View {
        @Environment(\.accent) private var accent
        let title: String
        let value: String
        var highlight = false

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(highlight ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(Color.primary))
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Operazioni

private struct OptionsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let toolsMissing = model.e2fsTools == nil
        VStack(spacing: 0) {
            OptionRow(symbol: "arrow.down.right.and.arrow.up.left", title: "Riduci al minimo",
                      detail: "Porta la partizione Linux allo spazio davvero usato, come PiShrink. Sul Raspberry poi si espande con raspi-config.",
                      isOn: $model.optimizeOptions.shrink, disabled: toolsMissing)
            Divider().padding(.leading, 58).opacity(0.5)
            OptionRow(symbol: "eraser.fill", title: "Togli le cronologie",
                      detail: "Cancella .bash_history, .python_history e simili da /root e /home, solo nella copia.",
                      isOn: $model.optimizeOptions.clean, disabled: toolsMissing)
            Divider().padding(.leading, 58).opacity(0.5)
            OptionRow(symbol: "archivebox.fill", title: "Comprimi in .xz",
                      detail: "Il file da caricare su Drive: di solito 3-4 volte più piccolo. Lo legge anche Raspberry Pi Imager.",
                      isOn: $model.optimizeOptions.compress)
            if model.optimizeOptions.compress && model.optimizeOptions.rebuilds {
                Toggle("Conserva anche l'immagine non compressa (.img)", isOn: $model.optimizeOptions.keepUncompressed)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 58)
                    .padding(.bottom, 12)
            }
            if !model.optimizePlannedOutputs.isEmpty, model.optimizeProblem == nil {
                Divider().opacity(0.5)
                OutputsPreview(files: model.optimizePlannedOutputs)
                    .padding(.top, 12)
            }
        }
        .card(cornerRadius: 20, padding: 16)
        .animation(.easeInOut(duration: 0.2), value: model.optimizeOptions)
    }
}

private struct OptionRow: View {
    @Environment(\.accent) private var accent
    let symbol: String
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var disabled = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn && !disabled ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
                    .frame(width: 40, height: 40)
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isOn && !disabled ? Color.white : Color.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden()
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { if !disabled { isOn.toggle() } }
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

private struct OutputsPreview: View {
    let files: [URL]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.badge.plus").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(files.count == 1 ? "Verrà creato" : "Verranno creati").font(.caption).foregroundStyle(.secondary)
                ForEach(files, id: \.self) { url in
                    Text(url.lastPathComponent)
                        .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                }
                Text("con il suo .sha256, in " + (files[0].deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
        }
    }
}

/// e2fsprogs non c'e': spiega come installarlo (per ora da Homebrew).
private struct MissingToolsCard: View {
    @Environment(AppModel.self) private var model
    private let command = "brew install e2fsprogs"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Per ridurre e ripulire servono gli strumenti e2fsprogs", systemImage: "wrench.and.screwdriver.fill")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text("Installali una volta sola dal Terminale con Homebrew, poi premi «Ricontrolla». La sola compressione funziona anche senza.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Text(command)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: { Label("Copia", systemImage: "doc.on.doc") }
                    .buttonStyle(.secondaryAction)
                Button("Ricontrolla") { model.refreshTools() }.buttonStyle(.secondaryAction)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: 20, padding: 18)
    }
}
