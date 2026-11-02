import Foundation
import SDCore

/// sdclone backup <diskN> [-o file.img|cartella] [--full] [--force] [--xz]
///                        [--status-file f] [--cancel-file f] [--as-user uid]   (questi ultimi tre li usa l'app)
func runBackup(_ args: [String]) throws {
    var rest = args
    let full = rest.removeAllFlag("--full")
    let force = rest.removeAllFlag("--force")
    let compress = rest.removeAllFlag("--xz")
    let output = try rest.takeOption("-o")
    let statusFile = try rest.takeOption("--status-file")
    let cancelFile = try rest.takeOption("--cancel-file")
    explicitUser = try rest.takeOption("--as-user").flatMap { uid_t($0) }
    guard rest.count == 1 else { throw CLIError("uso: sdclone backup <diskN> [-o file.img] [--full] [--force] [--xz]") }

    let channel = JobChannel(statusFile: statusFile, cancelFile: cancelFile)
    do {
        try backup(disk: rest[0], output: output, full: full, force: force, compress: compress, channel: channel)
    } catch {
        channel.failed(error)
        throw error
    }
}

private func backup(disk identifier: String, output: String?, full: Bool, force: Bool, compress: Bool, channel: JobChannel) throws {
    let disk = try selectableDisk(identifier)
    try requireRoot("Il backup (lettura di /dev/rdisk)")
    channel.starting()
    let destination = try resolveDestination(output, force: force, compressed: compress)

    let engine = BackupEngine()
    let layout = try engine.layout(of: disk.rawDevicePath, diskSize: disk.sizeBytes)
    let length = full ? disk.sizeBytes : layout.usedBytes

    print("Sorgente:     \(describe(disk))")
    print("Destinazione: \(destination.path)")
    print("Da copiare:   \(ByteFormat.string(length)) di \(ByteFormat.string(disk.sizeBytes))" +
          (full ? " (--full)" : layout.scheme == .mbr ? " (fino alla fine dell'ultima partizione)" : " (tabella non MBR: disco intero)"))

    // Smontato il disco e' coerente durante la lettura. Se non si smonta si va avanti lo stesso: si legge soltanto.
    do { try DiskControl.unmount(disk) }
    catch { print("Avviso: impossibile smontare \(disk.identifier), il backup potrebbe non essere coerente.") }
    defer { try? DiskControl.mount(disk) }

    let started = Date()
    let result = try engine.run(source: disk.rawDevicePath, length: length, destination: destination, compress: compress,
                                progress: { channel.progress($0, phase: .copying, label: "Backup") },
                                isCancelled: { channel.isCancelled })

    let sidecar = destination.appendingPathExtension("sha256")
    // Lo SHA256 e' sempre quello dell'immagine non compressa: cosi' resta valido anche dopo averla decompressa.
    let rawName = compress ? String(destination.lastPathComponent.dropLast(3)) : destination.lastPathComponent
    try "\(result.sha256)  \(rawName)\n".write(to: sidecar, atomically: true, encoding: .utf8)
    giveToInvokingUser(destination)
    giveToInvokingUser(sidecar)
    channel.finishedOK(sha256: result.sha256, output: destination.path, outputBytes: result.outputBytes)

    print("Fatto in \(humanDuration(Date().timeIntervalSince(started))). SHA256 dell'immagine: \(result.sha256)")
    if compress {
        print("File compresso: \(ByteFormat.string(result.outputBytes)) invece di \(ByteFormat.string(result.bytesCopied)).")
        print("Verifica in seguito con: xz -dc \"\(destination.path)\" | shasum -a 256")
    } else {
        print("Verifica in seguito con: shasum -a 256 -c \"\(sidecar.path)\"")
    }
}

private func resolveDestination(_ output: String?, force: Bool, compressed: Bool) throws -> URL {
    let fm = FileManager.default
    let autoName = BackupLibrary.newFileName(compressed: compressed)

    var file: URL
    if let output {
        let url = URL(fileURLWithPath: (output as NSString).expandingTildeInPath)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            file = url.appendingPathComponent(autoName)
        } else {
            file = url
        }
        if compressed && !file.lastPathComponent.lowercased().hasSuffix(".xz") {
            file = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".xz")
        }
    } else {
        file = BackupLibrary.defaultDirectory(home: invokingUserHome()).appendingPathComponent(autoName)
    }

    let dir = file.deletingLastPathComponent()
    if !fm.fileExists(atPath: dir.path) {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        giveToInvokingUser(dir)
    }
    if fm.fileExists(atPath: file.path) && !force {
        throw CLIError("\(file.path) esiste gia' (usa --force per sovrascriverlo)")
    }
    return file
}
