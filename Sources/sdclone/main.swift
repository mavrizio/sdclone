import Foundation
import SDCore

let usage = """
sdclone - clona e ripristina schede SD per Raspberry Pi

USO:
  sdclone list [--all]     elenca i dischi; --all mostra anche quelli bloccati

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
    case "list":
        try printDisks(showAll: args.contains("--all"))
    default:
        print(usage)
        exit(args.isEmpty ? 0 : 64)
    }
} catch {
    FileHandle.standardError.write(Data("Errore: \(error)\n".utf8))
    exit(1)
}
