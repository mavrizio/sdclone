import Foundation
import SDCore

/// sdclone optimize <immagine> [--no-shrink] [--clean] [--no-xz] [--keep-img] [-o cartella]
/// Riduce la partizione Linux al minimo, toglie le cronologie e comprime. Lavora su file nuovi: l'originale non si tocca.
/// Non serve root. Richiede e2fsprogs (brew install e2fsprogs).
func runOptimize(_ args: [String]) throws {
    var rest = args
    let options = ImageOptimizer.Options(shrink: !rest.removeAllFlag("--no-shrink"),
                                         clean: rest.removeAllFlag("--clean"),
                                         compress: !rest.removeAllFlag("--no-xz"),
                                         keepUncompressed: rest.removeAllFlag("--keep-img"))
    let output = try rest.takeOption("-o")
    guard rest.count == 1 else {
        throw CLIError("uso: sdclone optimize <immagine> [--no-shrink] [--clean] [--no-xz] [--keep-img] [-o cartella]")
    }
    let image = URL(fileURLWithPath: (rest[0] as NSString).expandingTildeInPath)
    let directory = output.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }

    let analysis = try ImageOptimizer.analyze(image)
    print("Immagine:  \(image.path)  (\(ByteFormat.string(analysis.imageBytes))\(analysis.isCompressed ? ", compressa" : ""))")
    print("Linux:     partizione \(analysis.root.number), \(ByteFormat.string(analysis.root.sizeBytes))")
    if options.shrink, let estimate = analysis.estimatedShrunkBytes {
        print("Stima:     circa \(ByteFormat.string(estimate)) dopo la riduzione")
    }

    let channel = JobChannel(statusFile: nil, cancelFile: nil)
    let labels: [ImageOptimizer.Step: String] = [
        .extracting: "Estrazione  ", .checking: "Controllo del filesystem (e2fsck)...",
        .cleaning: "Pulizia delle cronologie...", .shrinking: "Riduzione al minimo (resize2fs)...",
        .assembling: "Ricomposizione", .verifying: "Verifica    ", .compressing: "Compressione",
    ]
    var lastStep: ImageOptimizer.Step?
    let started = Date()
    let result = try ImageOptimizer().run(
        image: image, options: options, outputDirectory: directory,
        progress: { p in
            if let t = p.transfer {
                channel.progress(t, phase: .copying, label: labels[p.step] ?? "")
            } else if p.step != lastStep {
                print(labels[p.step] ?? "")
            }
            lastStep = p.step
        },
        isCancelled: { channel.isCancelled })
    print("")

    print("Fatto in \(humanDuration(Date().timeIntervalSince(started))).")
    print("Immagine:  \(ByteFormat.string(result.originalBytes))  ->  \(ByteFormat.string(result.imageBytes))")
    if let packed = result.compressedBytes { print("Compressa: \(ByteFormat.string(packed))") }
    for path in result.removedFiles { print("Tolto:     \(path)") }
    if options.clean && result.removedFiles.isEmpty { print("Pulizia:   nessuna cronologia trovata") }
    for file in result.files { print("Creato:    \(file.path)") }
    print("SHA256:    \(result.sha256)")
    if options.shrink {
        print("Nota: l'immagine ridotta NON si riespande da sola. Dopo l'avvio sul Raspberry: sudo raspi-config nonint do_expand_rootfs && sudo reboot")
    }
}
