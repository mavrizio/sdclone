import Foundation
import SDCore

/// sdclone restore <immagine.img> <diskN> [--confirm diskN] [--status-file f] [--cancel-file f] [--as-user uid]
/// Sovrascrive per intero la SD di destinazione. Da terminale chiede di digitare il nome del disco;
/// `--confirm` e' per l'app, che ha gia' chiesto la stessa conferma all'utente: deve coincidere col disco.
func runRestore(_ args: [String]) throws {
    var rest = args
    let confirm = try rest.takeOption("--confirm")
    let statusFile = try rest.takeOption("--status-file")
    let cancelFile = try rest.takeOption("--cancel-file")
    explicitUser = try rest.takeOption("--as-user").flatMap { uid_t($0) }
    guard rest.count == 2 else { throw CLIError("uso: sdclone restore <immagine.img> <diskN>") }

    let channel = JobChannel(statusFile: statusFile, cancelFile: cancelFile)
    do {
        try restore(image: rest[0], disk: rest[1], confirm: confirm, channel: channel)
    } catch {
        channel.failed(error)
        throw error
    }
}

private func restore(image path: String, disk identifier: String, confirm: String?, channel: JobChannel) throws {
    let image = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    let disk = try selectableDisk(identifier)

    let engine = RestoreEngine()
    let imageBytes = try engine.imageSize(image)
    guard imageBytes <= disk.sizeBytes else {
        throw TransferError.imageTooLarge(image: imageBytes, capacity: disk.sizeBytes)
    }
    try requireRoot("Il ripristino (scrittura su /dev/rdisk)")

    print("Immagine:     \(image.path)  (\(ByteFormat.string(imageBytes)))")
    print("Destinazione: \(describe(disk))")
    if let confirm {
        guard confirm == disk.identifier else {
            throw CLIError("la conferma (\(confirm)) non coincide col disco di destinazione (\(disk.identifier))")
        }
    } else {
        guard isatty(STDIN_FILENO) != 0 else {
            throw CLIError("il ripristino chiede una conferma e richiede un terminale interattivo")
        }
        print("")
        print("ATTENZIONE: tutto il contenuto di \(disk.identifier) verra' CANCELLATO e sostituito dall'immagine.")
        FileHandle.standardOutput.write(Data("Per confermare digita il nome del disco (\(disk.identifier)): ".utf8))
        guard readLine()?.trimmingCharacters(in: .whitespaces) == disk.identifier else {
            print("Annullato: nessuna modifica fatta.")
            return
        }
    }

    channel.starting()
    // Da qui all'espulsione macOS non deve montare la scheda: scriverebbe sui volumi e la verifica fallirebbe.
    let blocker = MountBlocker(wholeDisk: disk.identifier)
    if blocker == nil { print("Avviso: non riesco a impedire a macOS di montare \(disk.identifier) durante il lavoro.") }
    defer { withExtendedLifetime(blocker) {} }
    // La destinazione sta per essere cancellata (conferma gia' data): si riprova e, se serve, si forza lo smontaggio.
    do {
        if try DiskControl.unmountForOverwrite(disk, onRetry: { print("Avviso: \($0)") }) {
            print("Smontaggio forzato di \(disk.identifier).")
        }
    } catch {
        throw CLIError("impossibile smontare \(disk.identifier) nemmeno forzando: \(error). Espellila e reinseriscila, poi riprova.")
    }

    let started = Date()
    let result: RestoreResult
    do {
        result = try engine.run(image: image, target: disk.rawDevicePath, targetCapacity: disk.sizeBytes,
                                progress: { p in
                                    switch p.phase {
                                    case .writing: channel.progress(p.transfer, phase: .copying, label: "Scrittura")
                                    case .verifying: channel.progress(p.transfer, phase: .verifying, label: "Verifica ")
                                    }
                                },
                                isCancelled: { channel.isCancelled })
    } catch {
        print("La SD potrebbe essere rimasta a meta': non avviarla, rifai il ripristino.")
        throw error
    }
    channel.finishedOK(sha256: result.sha256, output: nil)

    print("Scrittura e verifica completate in \(humanDuration(Date().timeIntervalSince(started))). SHA256: \(result.sha256)")
    let sidecar = image.appendingPathExtension("sha256")
    if let expected = BackupLibrary.sha256(forImage: image) {
        print(expected == result.sha256 ? "Coincide con \(sidecar.lastPathComponent)."
                                        : "ATTENZIONE: l'immagine non coincide con \(sidecar.lastPathComponent): potrebbe essere stata modificata.")
    }
    do { try DiskControl.eject(disk); print("\(disk.identifier) espulso: puoi rimuovere la SD.") }
    catch { print("Non sono riuscito a espellere \(disk.identifier): fallo dal Finder.") }
}
