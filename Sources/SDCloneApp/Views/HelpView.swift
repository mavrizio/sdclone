import SwiftUI
import AppKit

/// Finestra della Guida: argomenti a sinistra, testo a destra, ricerca.
struct HelpView: View {
    @AppStorage("help.topic") private var selectedID = HelpContent.topics[0].id
    @State private var query = ""

    private var filtered: [HelpTopic] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? HelpContent.topics : HelpContent.topics.filter { $0.searchableText.contains(q) }
    }

    var body: some View {
        NavigationSplitView {
            List(filtered, selection: Binding(get: { selectedID }, set: { if let id = $0 { selectedID = id } })) { topic in
                Label(topic.title, systemImage: topic.symbol).tag(topic.id)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .overlay {
                if filtered.isEmpty {
                    Text("Nessun risultato").foregroundStyle(.secondary)
                }
            }
        } detail: {
            let topic = HelpContent.topics.first { $0.id == selectedID } ?? HelpContent.topics[0]
            ScrollView {
                HelpTopicView(topic: topic)
                    .padding(32)
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppBackground(accent: .backup).opacity(0.6))
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Cerca nella Guida")
        .onChange(of: query) {
            if let first = filtered.first, !filtered.contains(where: { $0.id == selectedID }) { selectedID = first.id }
        }
        .frame(minWidth: 760, idealWidth: 900, minHeight: 520, idealHeight: 640)
    }
}

struct HelpTopicView: View {
    let topic: HelpTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Accent.backup.gradient)
                        .frame(width: 46, height: 46)
                    Image(systemName: topic.symbol).font(.system(size: 21, weight: .semibold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.title).font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(topic.summary).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 4)

            ForEach(Array(topic.blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let s):
                    Text(.init(s)).font(.system(size: 14)).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                case .steps(let list):
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(Array(list.enumerated()), id: \.offset) { i, s in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(i + 1)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(Accent.backup.gradient))
                                Text(.init(s)).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                case .command(let c):
                    CommandBox(command: c)
                case .tip(let s):
                    Callout(text: s, symbol: "lightbulb.fill", tint: .yellow)
                case .warning(let s):
                    Callout(text: s, symbol: "exclamationmark.triangle.fill", tint: .orange)
                }
            }
        }
        .textSelection(.enabled)
    }
}

private struct CommandBox: View {
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            Text(command)
                .font(.system(size: 12.5, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.plain)
            .foregroundStyle(copied ? Color.green : Color.secondary)
            .help("Copia")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
    }
}

private struct Callout: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(.init(text)).font(.system(size: 13.5)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.3), lineWidth: 1))
    }
}
