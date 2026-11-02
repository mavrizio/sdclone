import Foundation
import AppKit
import SDCore

/// Dati dell'app mostrati in Informazioni, Guida e Avvertenze.
enum AppInfo {
    static let name = "SD Clone"
    static let tagline = "Backup, ottimizzazione e ripristino delle schede SD per Raspberry Pi"
    static let author = "Maurizio Tolfa"
    static let firstYear = 2026

    static var version: String { SDCloneVersion.marketing }
    static var build: String { SDCloneVersion.build }

    static var copyright: String {
        let year = Calendar.current.component(.year, from: Date())
        return year > firstYear ? "© \(firstYear)–\(year) \(author)" : "© \(firstYear) \(author)"
    }

    static let projectURL = URL(string: "https://github.com/mavrizio/sdclone")!
    static let issuesURL = URL(string: "https://github.com/mavrizio/sdclone/issues")!
    /// Icona dell'app (anche quando l'eseguibile gira fuori dal pacchetto, dove macOS darebbe quella generica).
    static var icon: NSImage { NSImage(named: "AppIcon") ?? NSApp.applicationIconImage }

    static let e2fsprogsURL = URL(string: "https://e2fsprogs.sourceforge.net")!
}
