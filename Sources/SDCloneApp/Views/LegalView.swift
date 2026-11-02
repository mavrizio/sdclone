import SwiftUI
import AppKit

/// Avvertenze, privacy e componenti di terze parti, in italiano e in inglese.
struct LegalView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case disclaimer, license, privacy, thirdParty
        var id: String { rawValue }

        func title(_ l: Legal.Language) -> String {
            switch self {
            case .disclaimer: return l == .italian ? "Avvertenze" : "Disclaimer"
            case .license: return l == .italian ? "Licenza" : "Licence"
            case .privacy: return "Privacy"
            case .thirdParty: return l == .italian ? "Terze parti" : "Third parties"
            }
        }
    }

    @AppStorage("legal.tab") private var tabRaw = Tab.disclaimer.rawValue
    @AppStorage("legal.language") private var languageRaw = Legal.Language.preferred.rawValue

    private var language: Legal.Language { Legal.Language(rawValue: languageRaw) ?? .italian }

    var body: some View {
        let tab = Tab(rawValue: tabRaw) ?? .disclaimer
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $tabRaw) {
                    ForEach(Tab.allCases) { Text($0.title(language)).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 420)
                Spacer()
                LanguagePicker(selection: $languageRaw)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case .disclaimer: DisclaimerText(language: language)
                    case .license:
                        Text(tab.title(language)).font(.system(size: 22, weight: .bold, design: .rounded))
                        Text(Legal.licenseIntro(language)).font(.body).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(Legal.mitLicense)
                            .font(.system(size: 12, design: .monospaced))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
                    case .privacy:
                        Text(Legal.privacyTitle(language)).font(.system(size: 22, weight: .bold, design: .rounded))
                        Text(Legal.privacy(language)).font(.body).fixedSize(horizontal: false, vertical: true)
                    case .thirdParty:
                        Text(tab.title(language)).font(.system(size: 22, weight: .bold, design: .rounded))
                        SectionsText(sections: Legal.thirdParty(language))
                    }
                }
                .textSelection(.enabled)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 640, idealWidth: 680, minHeight: 480, idealHeight: 640)
    }
}

struct LanguagePicker: View {
    @Binding var selection: String

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(Legal.Language.allCases) { Text($0.label).tag($0.rawValue) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 170)
    }
}

/// Il testo completo delle avvertenze (usato nella finestra e nel foglio del primo avvio).
struct DisclaimerText: View {
    let language: Legal.Language

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Legal.disclaimerTitle(language)).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(Legal.disclaimerIntro(language)).font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SectionsText(sections: Legal.disclaimer(language))
            Text(AppInfo.copyright).font(.caption).foregroundStyle(.tertiary)
        }
    }
}

private struct SectionsText: View {
    let sections: [Legal.Section]

    var body: some View {
        ForEach(sections) { s in
            VStack(alignment: .leading, spacing: 5) {
                Text(s.title).font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(s.body).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Al primo avvio (e quando le avvertenze cambiano) bisogna accettarle prima di usare l'app.
struct DisclaimerSheet: View {
    @AppStorage("legal.language") private var languageRaw = Legal.Language.preferred.rawValue
    @AppStorage("disclaimer.acceptedRevision") private var acceptedRevision = 0
    @State private var agreed = false

    private var language: Legal.Language { Legal.Language(rawValue: languageRaw) ?? .italian }
    private var it: Bool { language == .italian }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: AppInfo.icon).resizable().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(it ? "Benvenuto in SD Clone" : "Welcome to SD Clone")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(it ? "Prima di iniziare, leggi e accetta le avvertenze." : "Before you start, please read and accept the disclaimer.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                LanguagePicker(selection: $languageRaw)
            }
            .padding(22)
            Divider()
            ScrollView {
                DisclaimerText(language: language)
                    .textSelection(.enabled)
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 330)
            Divider()
            HStack(spacing: 12) {
                Toggle(it ? "Ho letto le avvertenze e le accetto" : "I have read and accept the disclaimer", isOn: $agreed)
                    .toggleStyle(.checkbox)
                Spacer()
                Button(it ? "Esci" : "Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.secondaryAction)
                Button(it ? "Accetto e continuo" : "Accept and continue") { acceptedRevision = Legal.disclaimerRevision }
                    .buttonStyle(.primaryAction)
                    .disabled(!agreed)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(width: 640)
        .interactiveDismissDisabled()
    }
}
