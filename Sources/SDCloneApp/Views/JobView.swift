import SwiftUI
import AppKit
import SDCore

/// Avanzamento di un backup/ripristino e, a lavoro finito, il suo esito.
struct JobView: View {
    @Environment(AppModel.self) private var model
    let run: JobRun

    var body: some View {
        VStack(spacing: 28) {
            StepsBar(run: run)
            if let outcome = run.outcome {
                ResultSection(run: run, outcome: outcome)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            } else {
                RunningSection(run: run)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 40)
        .frame(maxWidth: 760, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: run.isFinished)
    }
}

// MARK: - Tappe

private struct StepsBar: View {
    let run: JobRun
    @Environment(\.accent) private var accent

    /// Con molte tappe (ottimizzazione) i nomi non ci stanno: si scrive solo quello della tappa in corso.
    private var compact: Bool { run.steps.count > 4 }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(run.steps.enumerated()), id: \.offset) { i, title in
                let done = i < run.activeStep || run.outcome == .success
                let active = i == run.activeStep && run.outcome != .success
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(done || active ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(Color.primary.opacity(0.10)))
                            .frame(width: 22, height: 22)
                        if done {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                        } else {
                            Text("\(i + 1)").font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(active ? .white : .secondary)
                        }
                    }
                    .shadow(color: active ? accent.start.opacity(0.6) : .clear, radius: 8)
                    if !compact || active {
                        Text(title)
                            .font(.system(size: 13, weight: active ? .semibold : .medium, design: .rounded))
                            .foregroundStyle(done || active ? .primary : .secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .help(title)
                if i < run.steps.count - 1 {
                    Capsule()
                        .fill(i < run.activeStep || run.outcome == .success ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(Color.primary.opacity(0.10)))
                        .frame(height: 3)
                        .frame(maxWidth: 70)
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: run.activeStep)
    }
}

// MARK: - In corso

private struct RunningSection: View {
    @Environment(AppModel.self) private var model
    let run: JobRun

    private var indeterminate: Bool { run.waitingForAuthorization || run.status.bytesTotal == 0 }

    var body: some View {
        let s = run.status
        VStack(spacing: 26) {
            ZStack {
                ProgressRing(fraction: s.fraction, lineWidth: 24, accent: run.accent, indeterminate: indeterminate)
                    .frame(width: 270, height: 270)
                if indeterminate {
                    Image(systemName: run.waitingForAuthorization ? "lock.fill" : run.kind == .optimize ? "wand.and.stars" : "sdcard.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(run.accent.gradient)
                } else {
                    VStack(spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(Int(s.fraction * 100))")
                                .font(.system(size: 76, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText(value: s.fraction))
                            Text("%")
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Text(progressWord)
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }

            VStack(spacing: 6) {
                Text(run.title).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(run.phaseLabel).font(.system(size: 15)).foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }

            HStack(spacing: 14) {
                StatTile(symbol: "speedometer", title: "Velocità",
                         value: s.bytesPerSecond > 0 ? "\(ByteFormat.string(UInt64(s.bytesPerSecond)))/s" : "—")
                StatTile(symbol: "hourglass", title: "Tempo rimanente",
                         value: s.secondsRemaining.map { Self.friendly($0) } ?? "calcolo…")
                StatTile(symbol: "externaldrive.fill", title: "Trasferiti",
                         value: s.bytesTotal > 0 ? "\(ByteFormat.string(s.bytesDone)) / \(ByteFormat.string(s.bytesTotal))" : "—")
            }

            if run.speedHistory.count > 2 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Velocità nel tempo").font(.caption).foregroundStyle(.secondary)
                    Sparkline(values: run.speedHistory, accent: run.accent).frame(height: 64)
                }
                .card(cornerRadius: 18, padding: 14)
            }

            HStack(spacing: 14) {
                Button(run.cancelRequested ? "Annullamento…" : "Annulla") { model.cancelJob() }
                    .buttonStyle(.secondaryAction)
                    .disabled(run.cancelRequested || run.waitingForAuthorization)
                Label(run.kind == .restore ? "Non estrarre la scheda e non spegnere il Mac."
                      : run.kind == .compress || run.kind == .optimize ? "Il file originale non viene modificato."
                      : "Non estrarre la scheda finché non è finito.",
                      systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var progressWord: String {
        switch run.kind {
        case .compress: return "compresso"
        case .backup: return "copiato"
        case .restore: return run.status.phase == .verifying ? "verificato" : "scritto"
        case .optimize:
            switch run.optimizeStep {
            case .extracting?: return "estratto"
            case .assembling?: return "ricomposto"
            case .verifying?: return "verificato"
            default: return "compresso"
            }
        }
    }

    /// "4 min 12 s" invece di "04:12".
    static func friendly(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        if t >= 3600 { return "\(t / 3600) h \((t % 3600) / 60) min" }
        if t >= 60 { return "\(t / 60) min \(t % 60) s" }
        return "\(t) s"
    }
}

private struct StatTile: View {
    @Environment(\.accent) private var accent
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: 18, padding: 14)
    }
}

// MARK: - Esito

private struct ResultSection: View {
    @Environment(AppModel.self) private var model
    let run: JobRun
    let outcome: JobRun.Outcome

    private var kind: OutcomeBadge.Kind {
        switch outcome {
        case .success: return .success
        case .failed: return .failure
        case .cancelled: return .cancelled
        }
    }

    private var accent: Accent {
        switch outcome {
        case .success: return .success
        case .failed: return .failure
        case .cancelled: return .neutral
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            OutcomeBadge(kind: kind, size: 190)

            VStack(spacing: 8) {
                Text(run.title).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(detail).font(.system(size: 15)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520)
            }

            if outcome == .success { successCard }
            if case .failed = outcome, run.status.needsFullDiskAccess == true {
                DiskAccessHelp()
            } else if case .failed(let message) = outcome {
                Text(message)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: 560, alignment: .leading)
                    .card(cornerRadius: 16, padding: 14)
            }

            HStack(spacing: 12) {
                if outcome == .success && run.kind != .restore {
                    Button { model.reveal(run.file) } label: { Label("Mostra nel Finder", systemImage: "magnifyingglass") }
                        .buttonStyle(.primaryAction)
                    if let disk = run.disk {
                        let present = model.disks.contains { $0.identifier == disk.identifier }
                        let busy = model.ejecting.contains(disk.identifier)
                        Button { model.eject(disk) } label: {
                            Label(busy ? "Espulsione…" : present ? "Espelli la SD" : "SD espulsa",
                                  systemImage: present || busy ? "eject.fill" : "checkmark")
                        }
                        .buttonStyle(.secondaryAction)
                        .disabled(!present || busy)
                    }
                    Button("Fine") { model.dismissJob() }.buttonStyle(.secondaryAction)
                } else {
                    Button(outcome == .success ? "Fine" : "Chiudi") { model.dismissJob() }
                        .buttonStyle(.primaryAction)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .environment(\.accent, accent)
        }
    }

    private var detail: String {
        switch (run.kind, outcome) {
        case (.backup, .success):
            return "«\(run.file.lastPathComponent)» è pronto, con il suo controllo di integrità. Puoi togliere la scheda."
        case (.restore, .success):
            return "La scheda è stata riletta e coincide con l'immagine. È stata espulsa: puoi rimuoverla."
        case (.optimize, .success):
            let r = run.optimizeResult
            let removed = r.map { $0.removedFiles.isEmpty ? "" : " Cronologie tolte: \($0.removedFiles.count)." } ?? ""
            return "«\(run.file.lastPathComponent)» è pronto e controllato. L'immagine di partenza è rimasta com'era.\(removed)"
        case (.compress, .success):
            return "«\(run.file.lastPathComponent)» è pronto. Lo SHA256 dei dati è identico a quello dell'immagine originale, che è rimasta dov'era."
        case (.backup, .failed), (.compress, .failed), (.optimize, .failed):
            return "Il file parziale è stato eliminato, quindi non resta nulla di incompleto."
        case (.restore, .failed):
            return "La scheda potrebbe essere rimasta a metà: non avviarla e rifai il ripristino."
        case (.backup, .cancelled), (.compress, .cancelled), (.optimize, .cancelled):
            return "Hai annullato l'operazione. Nessun file è stato lasciato a metà."
        case (.restore, .cancelled):
            return "Hai annullato il ripristino. La scheda potrebbe essere incompleta: rifallo prima di usarla."
        }
    }

    private var successCard: some View {
        VStack(spacing: 12) {
            if let r = run.optimizeResult {
                HStack(spacing: 24) {
                    ResultFact(title: "Durata", value: DurationFormat.string(run.elapsed))
                    ResultFact(title: "Prima", value: ByteFormat.string(r.originalBytes))
                    ResultFact(title: run.optimizeOptions.shrink ? "Ridotta" : "Immagine", value: ByteFormat.string(r.imageBytes))
                    if let packed = r.compressedBytes {
                        ResultFact(title: "Compressa", value: ByteFormat.string(packed))
                        ResultFact(title: "Riduzione", value: (Double(r.originalBytes) / Double(max(packed, 1))).formatted(.number.precision(.fractionLength(1))) + "×")
                    }
                }
                if run.optimizeOptions.shrink {
                    Divider().opacity(0.5)
                    CommandLine(caption: "Sul Raspberry, dopo il primo avvio, per usare tutta la scheda:",
                                command: "sudo raspi-config nonint do_expand_rootfs && sudo reboot")
                }
                if !r.removedFiles.isEmpty {
                    Divider().opacity(0.5)
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "eraser.fill").foregroundStyle(.secondary)
                        Text(r.removedFiles.joined(separator: "  ·  "))
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Spacer()
                    }
                }
            } else {
            HStack(spacing: 24) {
                ResultFact(title: "Durata", value: DurationFormat.string(run.elapsed))
                if run.status.bytesTotal > 0 {
                    ResultFact(title: run.kind == .restore ? "Scritti" : "Immagine", value: ByteFormat.string(run.status.bytesTotal))
                }
                if let out = run.status.outputBytes, out > 0, out < run.status.bytesTotal {
                    ResultFact(title: "File compresso", value: ByteFormat.string(out))
                    ResultFact(title: "Riduzione", value: (Double(run.status.bytesTotal) / Double(out)).formatted(.number.precision(.fractionLength(1))) + "×")
                }
                if run.elapsed > 1, run.status.bytesTotal > 0 {
                    ResultFact(title: "Velocità media",
                               value: "\(ByteFormat.string(UInt64(Double(run.status.bytesTotal) / run.elapsed)))/s")
                }
            }
            }
            if let sha = run.status.sha256 {
                Divider().opacity(0.5)
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    Text("SHA256").font(.caption).foregroundStyle(.secondary)
                    Text(sha)
                        .font(.system(size: 11.5, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(sha, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Copia")
                }
            }
        }
        .frame(maxWidth: 560)
        .card(cornerRadius: 20, padding: 18)
    }
}

/// Un comando da copiare, con la sua spiegazione.
private struct CommandLine: View {
    let caption: String
    let command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(caption).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill").foregroundStyle(.secondary)
                Text(command)
                    .font(.system(size: 11.5, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Copia")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// macOS nega l'accesso diretto ai dischi finche' l'app non ha "Accesso completo al disco".
private struct DiskAccessHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("macOS blocca l'accesso diretto alla scheda", systemImage: "lock.shield.fill")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            VStack(alignment: .leading, spacing: 6) {
                Text("1.  Apri Impostazioni di Sistema › Privacy e sicurezza › **Accesso completo al disco**.")
                Text("2.  Attiva l'interruttore di **SD Clone** (con **+** se non c'è).")
                Text("3.  Chiudi e riapri SD Clone, poi riprova.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            } label: { Label("Apri Impostazioni di Sistema", systemImage: "gearshape.fill") }
                .buttonStyle(.secondaryAction)
        }
        .frame(maxWidth: 560, alignment: .leading)
        .card(cornerRadius: 18, padding: 18)
    }
}

private struct ResultFact: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
