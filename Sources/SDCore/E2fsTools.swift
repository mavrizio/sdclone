import Foundation

/// Gli strumenti di e2fsprogs (Homebrew, keg-only: non sono nel PATH) usati da `ImageOptimizer`.
/// Lavorano sempre su un file con la sola partizione, tranne i comandi in sola lettura (`?offset=`).
public struct E2fsTools: Equatable, Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var resize2fs: String { directory.appendingPathComponent("resize2fs").path }
    public var e2fsck: String { directory.appendingPathComponent("e2fsck").path }
    public var debugfs: String { directory.appendingPathComponent("debugfs").path }

    /// Cartelle in cui cercarli: `SDCLONE_E2FSPROGS`, dentro l'app (in futuro), Homebrew Apple Silicon e Intel.
    public static func candidates(environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        var dirs: [URL] = []
        if let custom = environment["SDCLONE_E2FSPROGS"] { dirs.append(URL(fileURLWithPath: custom)) }
        if let res = Bundle.main.resourceURL { dirs.append(res.appendingPathComponent("e2fsprogs")) }
        dirs.append(URL(fileURLWithPath: "/opt/homebrew/opt/e2fsprogs/sbin"))
        dirs.append(URL(fileURLWithPath: "/usr/local/opt/e2fsprogs/sbin"))
        return dirs
    }

    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> E2fsTools {
        for dir in candidates(environment: environment) {
            let tools = E2fsTools(directory: dir)
            if [tools.resize2fs, tools.e2fsck, tools.debugfs].allSatisfy({ FileManager.default.isExecutableFile(atPath: $0) }) {
                return tools
            }
        }
        throw OptimizeError.missingE2fsprogs
    }

    // MARK: - Operazioni

    /// `e2fsck -fy`: corregge cio' che serve (anche il journal di un Pi spento male). Va bene 0 (pulito) o 1 (corretto).
    func repair(_ partition: String, isCancelled: @escaping () -> Bool) throws {
        let r = try run(e2fsck, ["-fy", partition], isCancelled: isCancelled)
        guard r.code <= 1 else { throw OptimizeError.toolFailed(tool: "e2fsck", code: r.code, output: r.output) }
    }

    /// `e2fsck -fn` in sola lettura sull'immagine composta: deve risultare perfettamente pulito.
    func checkReadOnly(_ image: String, offset: UInt64, isCancelled: @escaping () -> Bool) throws {
        let r = try run(e2fsck, ["-fn", "\(image)?offset=\(offset)"], isCancelled: isCancelled)
        guard r.code == 0 else {
            throw OptimizeError.verificationFailed("e2fsck non e' pulito sul risultato (codice \(r.code))\n" +
                                                   r.output.split(separator: "\n").suffix(6).joined(separator: "\n"))
        }
    }

    /// `resize2fs -M` sul file della partizione. Restituisce la nuova dimensione del filesystem in byte.
    func shrinkToMinimum(_ partition: String, isCancelled: @escaping () -> Bool) throws -> UInt64 {
        let r = try run(resize2fs, ["-M", partition], isCancelled: isCancelled)
        guard r.code == 0 else { throw OptimizeError.toolFailed(tool: "resize2fs", code: r.code, output: r.output) }
        guard let bytes = Self.filesystemBytes(fromResizeOutput: r.output) else {
            throw OptimizeError.toolFailed(tool: "resize2fs", code: 0, output: "risposta non riconosciuta:\n" + r.output)
        }
        return bytes
    }

    /// Stima in sola lettura (`resize2fs -P` e `debugfs stats` con `?offset=`) della dimensione minima del filesystem.
    /// `dumpe2fs` non capisce `?offset=`, `debugfs` si'.
    func estimatedMinimumBytes(of image: String, offset: UInt64) throws -> UInt64? {
        let target = "\(image)?offset=\(offset)"
        let p = try run(resize2fs, ["-P", target], isCancelled: { false })
        let h = try run(debugfs, ["-R", "stats", target], isCancelled: { false })
        guard let blocks = Self.number(after: "Estimated minimum size of the filesystem:", in: p.output),
              let blockSize = Self.number(after: "Block size:", in: h.output) else { return nil }
        return blocks * blockSize
    }

    /// Toglie dal filesystem i file con i nomi indicati da /root e da ogni cartella in /home.
    /// Restituisce i percorsi tolti; controlla poi che non ci siano piu'.
    func removeHistories(_ partition: String, names: Set<String>, isCancelled: @escaping () -> Bool) throws -> [String] {
        let homes = try listDirectory("/home", in: partition, isCancelled: isCancelled)
            .filter { $0.isDirectory && $0.name != "." && $0.name != ".." }
            .map { "/home/\($0.name)" }
        var targets: [String] = []
        for dir in ["/root"] + homes {
            for entry in try listDirectory(dir, in: partition, isCancelled: isCancelled)
            where !entry.isDirectory && names.contains(entry.name) {
                targets.append("\(dir)/\(entry.name)")
            }
        }
        targets = targets.filter { !$0.contains(where: { $0 == " " || $0 == "\"" || $0 == "\n" }) }
        guard !targets.isEmpty else { return [] }

        let script = FileManager.default.temporaryDirectory.appendingPathComponent("sdclone-debugfs-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: script) }
        try targets.map { "rm \($0)" }.joined(separator: "\n").appending("\n").write(to: script, atomically: true, encoding: .utf8)
        let r = try run(debugfs, ["-w", "-f", script.path, partition], isCancelled: isCancelled)
        guard r.code == 0 else { throw OptimizeError.toolFailed(tool: "debugfs", code: r.code, output: r.output) }

        // debugfs esce con 0 anche se un comando fallisce: si ricontrolla davvero.
        for path in targets {
            let dir = (path as NSString).deletingLastPathComponent, name = (path as NSString).lastPathComponent
            if try listDirectory(dir, in: partition, isCancelled: isCancelled).contains(where: { $0.name == name }) {
                throw OptimizeError.verificationFailed("\(path) e' ancora presente dopo la pulizia")
            }
        }
        return targets
    }

    struct DirEntry: Equatable {
        let name: String
        let isDirectory: Bool
    }

    /// `debugfs -R "ls -p DIR"` (sola lettura). Una cartella che non esiste da' una lista vuota.
    func listDirectory(_ dir: String, in partition: String, isCancelled: @escaping () -> Bool) throws -> [DirEntry] {
        let r = try run(debugfs, ["-R", "ls -p \(dir)", partition], isCancelled: isCancelled)
        guard r.code == 0 else { throw OptimizeError.toolFailed(tool: "debugfs", code: r.code, output: r.output) }
        return Self.parseList(r.output)
    }

    // MARK: - Lettura delle risposte

    /// Righe di `ls -p`: "/inode/modo/uid/gid/nome/dimensione/" (per le cartelle la dimensione e' vuota).
    static func parseList(_ output: String) -> [DirEntry] {
        output.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("/") else { return nil }
            let f = line.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
            guard f.count >= 5, f[1].count >= 2 else { return nil }
            return DirEntry(name: String(f[4]), isDirectory: f[1].hasPrefix("04"))
        }
    }

    /// "The filesystem on X is now 1514496 (4k) blocks long." oppure "... is already 1514496 (4k) blocks long."
    static func filesystemBytes(fromResizeOutput output: String) -> UInt64? {
        guard let r = output.range(of: #"(\d+) \((\d+)k\) blocks long"#, options: .regularExpression) else { return nil }
        let parts = output[r].split(separator: " ")
        guard let blocks = UInt64(parts[0]),
              let k = UInt64(parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "(k)"))) else { return nil }
        return blocks * k * 1024
    }

    static func number(after label: String, in output: String) -> UInt64? {
        guard let line = output.split(separator: "\n").first(where: { $0.contains(label) }) else { return nil }
        return UInt64(line.components(separatedBy: label).last?.trimmingCharacters(in: .whitespaces) ?? "")
    }

    // MARK: - Esecuzione

    /// Lancia lo strumento; se `isCancelled` diventa vero lo ferma e lancia `TransferError.cancelled`.
    /// L'output va in un file, non in una pipe: un output lungo non puo' bloccare il processo.
    func run(_ tool: String, _ arguments: [String], isCancelled: @escaping () -> Bool) throws -> (code: Int32, output: String) {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("sdclone-tool-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: log) }
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = arguments
        p.standardOutput = handle
        p.standardError = handle
        p.standardInput = FileHandle.nullDevice
        try p.run()
        while p.isRunning {
            if isCancelled() {
                p.terminate()
                p.waitUntilExit()
                throw TransferError.cancelled
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        return (p.terminationStatus, output)
    }
}
