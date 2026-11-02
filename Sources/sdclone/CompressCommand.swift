import Foundation
import SDCore

/// sdclone compress <file.img> [-o file.img.xz] [--force] [--status-file f] [--cancel-file f]
/// Comprime un'immagine gia' salvata in .xz. Non serve root: sono file dell'utente. L'originale non si tocca.
func runCompress(_ args: [String]) throws {
    var rest = args
    let force = rest.removeAllFlag("--force")
    let output = try rest.takeOption("-o")
    let statusFile = try rest.takeOption("--status-file")
    let cancelFile = try rest.takeOption("--cancel-file")
    guard rest.count == 1 else { throw CLIError("uso: sdclone compress <file.img> [-o file.img.xz] [--force]") }

    let channel = JobChannel(statusFile: statusFile, cancelFile: cancelFile)
    do {
        try compress(source: rest[0], output: output, force: force, channel: channel)
    } catch {
        channel.failed(error)
        throw error
    }
}

private func compress(source path: String, output: String?, force: Bool, channel: JobChannel) throws {
    let source = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    guard FileManager.default.fileExists(atPath: source.path) else { throw CLIError("\(source.path) non esiste") }
    guard !XZFormat.isXZ(source) else { throw CLIError("\(source.lastPathComponent) e' gia' compresso") }
    channel.starting()

    let destination = output.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        ?? source.appendingPathExtension("xz")
    if FileManager.default.fileExists(atPath: destination.path) && !force {
        throw CLIError("\(destination.path) esiste gia' (usa --force per sovrascriverlo)")
    }

    let length = try fileSizeOf(source)
    print("Sorgente:     \(source.path)  (\(ByteFormat.string(length)))")
    print("Destinazione: \(destination.path)")

    let started = Date()
    let result = try BackupEngine().run(source: source.path, length: length, destination: destination, compress: true,
                                        progress: { channel.progress($0, phase: .copying, label: "Compressione") },
                                        isCancelled: { channel.isCancelled })

    let sidecar = destination.appendingPathExtension("sha256")
    let rawName = destination.lastPathComponent.hasSuffix(".xz") ? String(destination.lastPathComponent.dropLast(3))
                                                                  : destination.lastPathComponent
    try "\(result.sha256)  \(rawName)\n".write(to: sidecar, atomically: true, encoding: .utf8)
    channel.finishedOK(sha256: result.sha256, output: destination.path, outputBytes: result.outputBytes)

    print("Fatto in \(humanDuration(Date().timeIntervalSince(started))): \(ByteFormat.string(result.outputBytes)) invece di \(ByteFormat.string(length)).")
    if let known = BackupLibrary.sha256(forImage: source) {
        print(known == result.sha256 ? "Lo SHA256 coincide con quello registrato per l'originale: i dati sono identici."
                                     : "ATTENZIONE: lo SHA256 non coincide con quello registrato per l'originale: il file originale potrebbe essere cambiato.")
    }
}

private func fileSizeOf(_ url: URL) throws -> UInt64 {
    let n = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    return UInt64(n)
}
