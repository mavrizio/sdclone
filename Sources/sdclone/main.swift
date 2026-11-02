import Foundation
import SDCore

let usage = """
sdclone - clona e ripristina schede SD per Raspberry Pi

USO:
  sdclone --version                          versione
  sdclone list [--all]                       elenca i dischi; --all mostra anche quelli bloccati
  sudo sdclone backup <diskN> [-o dest]      salva la SD in un .img (default ~/Documents/SDClone/)
        --full                               copia tutto il disco, non solo fino all'ultima partizione
        --xz                                 comprime al volo in .img.xz (di solito 4-8 volte piu' piccolo)
        --force                              sovrascrive il file di destinazione se esiste
  sudo sdclone restore <immagine> <diskN>    scrive l'immagine (.img o .img.xz) sulla SD e la verifica (chiede conferma)
  sdclone compress <file.img> [-o dest]      comprime un backup gia' fatto in .img.xz (senza sudo)
  sdclone optimize <immagine> [-o cartella]  riduce la partizione Linux al minimo e comprime in .min.img.xz (senza sudo)
        --clean                              toglie anche le cronologie (bash, python, less, vim...) da /root e /home
        --no-shrink                          non riduce (utile con --clean)
        --no-xz                              non comprime: produce un .min.img
        --keep-img                           con la compressione conserva anche il .min.img

"""

func printDisks(showAll: Bool) throws {
    let policy = SafetyPolicy.default
    let disks = try DiskEnumerator().allDisks().sorted { $0.identifier < $1.identifier }
    var shown = 0
    for disk in disks {
        let rejection = policy.rejection(for: disk)
        // Senza --all i dischi interni non vengono nemmeno mostrati.
        if rejection == nil || showAll {
            let vols = disk.volumeNames.isEmpty ? "" : "  [\(disk.volumeNames.joined(separator: ", "))]"
            let state = rejection.map { "BLOCCATO: \($0.message)" } ?? "ok"
            print("\(disk.identifier)\t\(ByteFormat.string(disk.sizeBytes))\t\(disk.busProtocol)\t\(disk.mediaName)\(vols)\t\(state)")
            shown += 1
        }
    }
    if shown == 0 { print("Nessuna SD trovata. Inseriscila e riprova (usa --all per vedere tutti i dischi).") }
}

let args = Array(CommandLine.arguments.dropFirst())
do {
    switch args.first {
    case "--version", "version":
        print("sdclone \(SDCloneVersion.full)")
    case "list":
        try printDisks(showAll: args.contains("--all"))
    case "backup":
        try runBackup(Array(args.dropFirst()))
    case "restore":
        try runRestore(Array(args.dropFirst()))
    case "compress":
        try runCompress(Array(args.dropFirst()))
    case "optimize":
        try runOptimize(Array(args.dropFirst()))
    default:
        print(usage)
        exit(args.isEmpty ? 0 : 64)
    }
} catch {
    FileHandle.standardError.write(Data("Errore: \(error)\n".utf8))
    exit(1)
}
