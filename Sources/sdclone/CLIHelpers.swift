import Foundation
import SDCore

struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

/// Impostata dal gestore di SIGINT: il motore la controlla a ogni blocco e si ferma pulito.
nonisolated(unsafe) var interrupted: sig_atomic_t = 0

func installInterruptHandler() {
    signal(SIGINT) { _ in interrupted = 1 }
}

func requireRoot(_ what: String) throws {
    guard geteuid() == 0 else {
        throw CLIError("\(what) richiede i privilegi di root. Rilancia con sudo, ad esempio: sudo .build/release/sdclone \(CommandLine.arguments.dropFirst().joined(separator: " "))")
    }
}

/// Trova il disco, controlla `SafetyPolicy` e lo restituisce. Unico ingresso per backup e ripristino.
func selectableDisk(_ identifier: String) throws -> DiskInfo {
    let id = identifier.hasPrefix("/dev/") ? String(identifier.dropFirst(5)) : identifier
    guard let disk = try DiskEnumerator().allDisks().first(where: { $0.identifier == id }) else {
        throw CLIError("disco \(id) non trovato (usa `sdclone list`)")
    }
    if let why = SafetyPolicy.default.rejection(for: disk) {
        throw CLIError("\(disk.identifier) rifiutato: \(why.message)")
    }
    return disk
}

func describe(_ disk: DiskInfo) -> String {
    let vols = disk.volumeNames.isEmpty ? "" : "  [\(disk.volumeNames.joined(separator: ", "))]"
    return "\(disk.identifier)  \(ByteFormat.string(disk.sizeBytes))  \(disk.busProtocol)  \(disk.mediaName)\(vols)"
}

// MARK: - Opzioni

extension Array where Element == String {
    /// Toglie ogni occorrenza di `flag` e dice se c'era.
    mutating func removeAllFlag(_ flag: String) -> Bool {
        let had = contains(flag)
        removeAll { $0 == flag }
        return had
    }

    /// Toglie `name valore` e restituisce il valore.
    mutating func takeOption(_ name: String) throws -> String? {
        guard let i = firstIndex(of: name) else { return nil }
        guard i + 1 < count else { throw CLIError("manca il valore dopo \(name)") }
        let value = self[i + 1]
        removeSubrange(i...(i + 1))
        return value
    }
}

// MARK: - Utente per conto del quale si lavora

/// Con sudo lo dice `SUDO_UID`; lanciato dall'app (osascript) lo dice `--as-user`.
nonisolated(unsafe) var explicitUser: uid_t?

private func invokingUser() -> (uid: uid_t, gid: gid_t)? {
    guard geteuid() == 0 else { return nil }
    let uid = explicitUser ?? ProcessInfo.processInfo.environment["SUDO_UID"].flatMap { uid_t($0) }
    guard let uid else { return nil }
    let gid = getpwuid(uid)?.pointee.pw_gid ?? gid_t(20)
    return (uid, gid)
}

/// Con root i file creati sarebbero di root: li restituisce all'utente vero.
func giveToInvokingUser(_ url: URL) {
    guard let user = invokingUser() else { return }
    chown(url.path, user.uid, user.gid)
}

func invokingUserHome() -> URL {
    if let user = invokingUser(), let pw = getpwuid(user.uid) {
        return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
    }
    return FileManager.default.homeDirectoryForCurrentUser
}

// MARK: - Barra di avanzamento nel terminale

final class ProgressBar {
    var label: String
    private var lastPrint = Date.distantPast
    init(label: String) { self.label = label }

    func show(_ p: TransferProgress, force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastPrint) >= 0.2 else { return }
        lastPrint = now
        let width = 28
        let filled = Int((p.fraction * Double(width)).rounded(.down))
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
        let speed = p.bytesPerSecond > 0 ? "\(ByteFormat.string(UInt64(p.bytesPerSecond)))/s" : "--"
        let line = String(format: "\r%@ [%@] %3d%%  %@ / %@  %@  restano %@   ",
                          label, bar, Int(p.fraction * 100),
                          ByteFormat.string(p.bytesDone), ByteFormat.string(p.bytesTotal),
                          speed, DurationFormat.string(p.secondsRemaining))
        FileHandle.standardOutput.write(Data(line.utf8))
    }

    func finish() { print("") }
}

// MARK: - Canale di avanzamento e annullamento

/// Dove vanno avanzamento e annullamento: terminale (barra e Ctrl-C) oppure file JSON (usato dall'app).
final class JobChannel {
    private let statusFile: URL?
    private let cancelFile: URL?
    private let bar = ProgressBar(label: "")
    private var status = JobStatus(state: .starting, phase: .preparing)
    private var lastWrite = Date.distantPast
    private var barOpen = false

    init(statusFile: String?, cancelFile: String?) {
        self.statusFile = statusFile.map { URL(fileURLWithPath: $0) }
        self.cancelFile = cancelFile.map { URL(fileURLWithPath: $0) }
        installInterruptHandler()
    }

    var isCancelled: Bool {
        if interrupted != 0 { return true }
        guard let cancelFile else { return false }
        return FileManager.default.fileExists(atPath: cancelFile.path)
    }

    func starting(_ phase: JobStatus.Phase = .preparing) {
        status.phase = phase
        status.state = .starting
        publish(force: true)
    }

    func progress(_ p: TransferProgress, phase: JobStatus.Phase, label: String) {
        if bar.label != label {
            closeBar()
            bar.label = label
        }
        barOpen = true
        status = status.updating(p, phase: phase)
        if statusFile == nil { bar.show(p) } else { publish() }
    }

    func finishedOK(sha256: String, output: String?, outputBytes: UInt64? = nil) {
        closeBar()
        status.state = .done
        status.phase = .finishing
        status.bytesDone = status.bytesTotal
        status.secondsRemaining = 0
        status.sha256 = sha256
        status.outputPath = output
        status.outputBytes = outputBytes
        publish(force: true)
    }

    func failed(_ error: Error) {
        closeBar()
        if case TransferError.cancelled = error { status.state = .cancelled } else { status.state = .failed }
        status.message = "\(error)"
        if case TransferError.accessBlockedByMacOS = error { status.needsFullDiskAccess = true }
        publish(force: true)
    }

    private func closeBar() {
        guard barOpen else { return }
        barOpen = false
        if statusFile == nil {
            bar.show(TransferProgress(bytesDone: status.bytesTotal, bytesTotal: status.bytesTotal,
                                      bytesPerSecond: 0, secondsRemaining: 0), force: true)
            bar.finish()
        }
    }

    private func publish(force: Bool = false) {
        guard let statusFile else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastWrite) >= 0.15 else { return }
        lastWrite = now
        try? status.write(to: statusFile)
        giveToInvokingUser(statusFile)
    }
}

func humanDuration(_ s: TimeInterval) -> String { DurationFormat.string(s) }
