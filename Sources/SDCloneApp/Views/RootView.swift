import SwiftUI
import SDCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("disclaimer.acceptedRevision") private var acceptedRevision = 0
    @AppStorage(Preferences.badgeKey) private var dockProgress = true

    /// Le avvertenze vanno accettate prima di usare l'app (non nelle foto dell'interfaccia).
    private var needsDisclaimer: Bool { acceptedRevision < Legal.disclaimerRevision && !Snapshot.isActive }

    /// Percentuale sull'icona nel Dock mentre si lavora.
    private var dockBadge: String? {
        guard dockProgress, let job = model.job, !job.isFinished, job.status.bytesTotal > 0 else { return nil }
        return "\(Int(job.status.fraction * 100))%"
    }

    private var accent: Accent {
        if let job = model.job {
            switch job.outcome {
            case nil: return job.accent
            case .success?: return .success
            case .failed?: return .failure
            case .cancelled?: return .neutral
            }
        }
        return model.mode.accent
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 232)
                .background(SidebarBackground().ignoresSafeArea())
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1).ignoresSafeArea()
                }

            ZStack {
                AppBackground(accent: accent)
                Group {
                    if let job = model.job {
                        JobView(run: job)
                    } else {
                        switch model.mode {
                        case .backup: BackupView()
                        case .optimize: OptimizeView()
                        case .restore: RestoreView()
                        case .library: LibraryView()
                        }
                    }
                }
                .id(model.job == nil ? model.mode.rawValue : "job")
                .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.25), value: model.mode)
            .animation(.easeInOut(duration: 0.25), value: model.job == nil)
        }
        .environment(\.accent, accent)
        .background { if !Snapshot.isActive { WindowConfigurator() } }
        .alert("Impossibile espellere la scheda",
               isPresented: Binding(get: { model.ejectError != nil }, set: { if !$0 { model.ejectError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.ejectError ?? "")
        }
        .sheet(isPresented: .constant(needsDisclaimer)) { DisclaimerSheet() }
        .onChange(of: dockBadge) { _, badge in NSApp.dockTile.badgeLabel = badge }
        .task {
            model.startMonitoring()
            model.applyDemoState()
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Accent.backup.gradient)
                        .frame(width: 38, height: 38)
                        .shadow(color: Accent.backup.start.opacity(0.5), radius: 8, y: 3)
                    Image(systemName: "sdcard.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("SD Clone").font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("per Raspberry Pi").font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 50)
            .padding(.bottom, 22)

            ForEach(Mode.allCases) { mode in
                SidebarItem(mode: mode, selected: model.mode == mode && model.job == nil, enabled: model.job == nil) {
                    model.mode = mode
                }
            }

            Spacer()

            SDStatus()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }
}

private struct SidebarItem: View {
    let mode: Mode
    let selected: Bool
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)
                Text(mode.sidebarTitle).font(.system(size: 14.5, weight: .medium, design: .rounded))
                Spacer()
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? AnyShapeStyle(mode.accent.gradient)
                                   : AnyShapeStyle(Color.primary.opacity(hovering && enabled ? 0.07 : 0)))
            )
            .shadow(color: selected ? mode.accent.start.opacity(0.4) : .clear, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled || selected ? 1 : 0.45)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
    }
}

private struct SDStatus: View {
    @Environment(AppModel.self) private var model
    @State private var pulse = false

    var body: some View {
        let n = model.disks.count
        HStack(spacing: 10) {
            ZStack {
                Circle().fill((n > 0 ? Color.green : Color.gray).opacity(0.25))
                    .frame(width: 18, height: 18)
                    .scaleEffect(pulse && n > 0 ? 1.35 : 1)
                    .opacity(pulse && n > 0 ? 0.2 : 1)
                Circle().fill(n > 0 ? Color.green : Color.gray).frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(n == 0 ? "Nessuna SD" : n == 1 ? "1 SD rilevata" : "\(n) SD rilevate")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                Text(model.demo ? "modalità demo" : "dischi del Mac protetti")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
        .onAppear { pulse = true }
    }
}
