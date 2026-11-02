import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Vibrancy nativa (sidebar traslucida, sfondi della finestra).
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .followsWindowActiveState
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

/// Rende la finestra trascinabile da qualsiasi punto dello sfondo, senza barra del titolo visibile.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.isMovableByWindowBackground = true
            w.minSize = NSSize(width: 980, height: 700)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Sfondo con macchie di colore sfocate che si spostano piano, nel colore della schermata.
struct AppBackground: View {
    let accent: Accent
    @Environment(\.colorScheme) private var scheme
    @State private var drift = false

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            GeometryReader { geo in
                let s = max(geo.size.width, geo.size.height)
                ZStack {
                    Circle().fill(accent.start)
                        .frame(width: s * 0.55)
                        .offset(x: drift ? -s * 0.10 : -s * 0.22, y: drift ? -s * 0.22 : -s * 0.10)
                    Circle().fill(accent.end)
                        .frame(width: s * 0.48)
                        .offset(x: drift ? s * 0.34 : s * 0.22, y: drift ? s * 0.28 : s * 0.40)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .blur(radius: 110)
                .opacity(scheme == .dark ? 0.38 : 0.26)
            }
            .animation(.easeInOut(duration: 9).repeatForever(autoreverses: true), value: drift)
            .animation(.easeInOut(duration: 1.0), value: accent.start)
        }
        .ignoresSafeArea()
        .onAppear { drift = true }
    }
}

/// Selettore di cartella/file del sistema.
enum Panels {
    @MainActor
    static func chooseFolder(start: URL?) -> URL? {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.canCreateDirectories = true
        p.prompt = "Scegli"
        p.directoryURL = start
        return p.runModal() == .OK ? p.url : nil
    }

    @MainActor
    static func chooseImage(start: URL?) -> URL? {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.allowedContentTypes = ["img", "xz"].compactMap { UTType(filenameExtension: $0) }
        p.prompt = "Scegli"
        p.directoryURL = start
        return p.runModal() == .OK ? p.url : nil
    }
}

/// `ScrollView` nell'app; in modalita' snapshot (ImageRenderer non disegna gli scroll) il contenuto e' messo direttamente.
struct Scrolling<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if Snapshot.isActive {
            content.frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView { content }
        }
    }
}

/// Vibrancy della sidebar; in modalita' snapshot un colore semplice (ImageRenderer non disegna le viste AppKit).
struct SidebarBackground: View {
    var body: some View {
        if Snapshot.isActive {
            Color(nsColor: .controlBackgroundColor).opacity(0.85)
        } else {
            VisualEffect(material: .sidebar)
        }
    }
}
