import SwiftUI
import SDCore

/// Elenco delle schede rilevate; se non ce ne sono mostra l'invito a inserirne una.
struct DiskPicker: View {
    @Environment(AppModel.self) private var model
    var requireFit: UInt64?   // dimensione minima richiesta (ripristino)

    var body: some View {
        if model.disks.isEmpty {
            EmptyDisksView()
        } else {
            VStack(spacing: 12) {
                ForEach(model.disks, id: \.identifier) { disk in
                    DiskRow(disk: disk,
                            selected: model.selectedDiskID == disk.identifier,
                            tooSmall: requireFit.map { $0 > disk.sizeBytes } ?? false,
                            ejecting: model.ejecting.contains(disk.identifier),
                            onEject: { model.eject(disk) }) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.select(disk) }
                    }
                }
            }
        }
    }
}

struct DiskRow: View {
    @Environment(\.accent) private var accent
    let disk: DiskInfo
    let selected: Bool
    var tooSmall = false
    var ejecting = false
    var onEject: (() -> Void)?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        let p = DiskInfoPresentation(disk: disk)
        Button(action: action) {
            HStack(spacing: 20) {
                SDCardView(width: 58, label: p.shortSize, caption: "SD", style: p.cardStyle)
                    .rotationEffect(.degrees(selected ? -4 : 0))
                    .scaleEffect(hovering || selected ? 1.06 : 1)
                    .frame(width: 70)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(p.title).font(.system(size: 17, weight: .semibold, design: .rounded))
                        Pill(text: disk.identifier)
                        if tooSmall { Pill(text: "TROPPO PICCOLA", tint: .red) }
                    }
                    Text(p.subtitle).font(.callout).foregroundStyle(.secondary)
                    if !disk.partitions.isEmpty {
                        PartitionBar(partitions: disk.partitions, total: disk.sizeBytes)
                        PartitionLegend(partitions: disk.partitions, total: disk.sizeBytes)
                    }
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.5).frame(width: 26, height: 26)
                    if selected {
                        Circle().fill(accent.gradient).frame(width: 26, height: 26)
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    }
                }
            }
            .card(cornerRadius: 22, padding: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(Color.clear), lineWidth: 2.5)
            )
            .shadow(color: selected ? accent.start.opacity(0.35) : .clear, radius: 18, y: 4)
            .opacity(tooSmall ? 0.55 : 1)
            .scaleEffect(hovering && !selected ? 1.008 : 1)
        }
        .buttonStyle(.plain)
        .disabled(tooSmall)
        .overlay(alignment: .topTrailing) {
            if let onEject {
                EjectButton(busy: ejecting, action: onEject).padding(.top, 10).padding(.trailing, 14)
            }
        }
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hovering)
    }
}

struct EmptyDisksView: View {
    @Environment(\.accent) private var accent
    @State private var bob = false

    var body: some View {
        VStack(spacing: 14) {
            SDCardView(width: 74, label: "SD", caption: "inserisci", style: .graphite)
                .opacity(0.9)
                .rotationEffect(.degrees(bob ? 5 : -5))
                .offset(y: bob ? -7 : 5)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: bob)
                .padding(.bottom, 8)
            Text("Inserisci una scheda SD")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("Il lettore integrato del Mac e gli adattatori USB vengono riconosciuti da soli.\nI dischi del Mac e gli SSD esterni non compaiono mai qui.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("In ascolto…").font(.callout).foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .card(cornerRadius: 24, padding: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(accent.start.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
        )
        .onAppear { bob = true }
    }
}

/// Piccolo pulsante tondo sulla scheda: smonta ed espelle la SD.
struct EjectButton: View {
    let busy: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(.regularMaterial)
                Circle().strokeBorder(Color.primary.opacity(hovering ? 0.25 : 0.12), lineWidth: 1)
                if busy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "eject.fill").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(hovering ? Color.primary : Color.secondary)
                }
            }
            .frame(width: 28, height: 28)
            .scaleEffect(hovering ? 1.1 : 1)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .help("Espelli la SD")
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
    }
}
