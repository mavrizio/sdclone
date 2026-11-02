import Foundation

/// Un backup trovato nella cartella dei backup.
public struct BackupEntry: Equatable, Sendable, Identifiable {
    public let url: URL
    public let sizeBytes: UInt64
    public let date: Date
    /// Letto dal file `.sha256` accanto all'immagine, se c'e'.
    public let sha256: String?
    /// Vero per i file `.img.xz`; `sizeBytes` e' allora la dimensione compressa.
    public let isCompressed: Bool
    /// Per i `.img.xz`: dimensione dell'immagine una volta decompressa (letta dall'indice, senza decomprimere).
    public let uncompressedBytes: UInt64?

    public init(url: URL, sizeBytes: UInt64, date: Date, sha256: String?, isCompressed: Bool = false,
                uncompressedBytes: UInt64? = nil) {
        self.url = url
        self.sizeBytes = sizeBytes
        self.date = date
        self.sha256 = sha256
        self.isCompressed = isCompressed
        self.uncompressedBytes = uncompressedBytes
    }

    public var id: URL { url }
    public var name: String {
        let n = url.lastPathComponent
        return String(isCompressed ? n.dropLast(".img.xz".count) : n.dropLast(".img".count))
    }
}

public enum BackupLibrary {
    /// ~/Documents/SDClone, o la cartella equivalente per l'utente indicato.
    public static func defaultDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Documents/SDClone", isDirectory: true)
    }

    static func isImage(_ url: URL) -> Bool { url.lastPathComponent.lowercased().hasSuffix(".img") }
    static func isCompressedImage(_ url: URL) -> Bool { url.lastPathComponent.lowercased().hasSuffix(".img.xz") }

    /// Le immagini `.img` e `.img.xz` della cartella, dalla piu' recente.
    public static func entries(in directory: URL) -> [BackupEntry] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return files
            .filter { isImage($0) || isCompressedImage($0) }
            .compactMap { url -> BackupEntry? in
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { return nil }
                return BackupEntry(url: url,
                                   sizeBytes: UInt64(v.fileSize ?? 0),
                                   date: v.contentModificationDate ?? .distantPast,
                                   sha256: sha256(forImage: url),
                                   isCompressed: isCompressedImage(url),
                                   uncompressedBytes: isCompressedImage(url) ? try? XZFormat.uncompressedSize(of: url) : nil)
            }
            .sorted { $0.date > $1.date }
    }

    /// Prima parola del file `<immagine>.sha256` (formato `shasum`).
    public static func sha256(forImage url: URL) -> String? {
        let sidecar = url.appendingPathExtension("sha256")
        guard let text = try? String(contentsOf: sidecar, encoding: .utf8),
              let word = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).first,
              word.count == 64 else { return nil }
        return String(word)
    }

    /// Nome file nella forma `sdclone-yyyyMMdd-HHmmss.img` (`.img.xz` se compresso).
    public static func newFileName(date: Date = Date(), compressed: Bool = false) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        return "sdclone-\(fmt.string(from: date)).img" + (compressed ? ".xz" : "")
    }
}
