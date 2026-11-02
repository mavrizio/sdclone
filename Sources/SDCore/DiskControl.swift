import Foundation

/// Smontaggio, rimontaggio ed espulsione tramite `diskutil`.
public enum DiskControl {
    /// Smonta tutti i volumi del disco: obbligatorio prima di scrivere sul nodo raw.
    public static func unmount(_ disk: DiskInfo, force: Bool = false) throws {
        _ = try DiskEnumerator.runDiskutil(["unmountDisk"] + (force ? ["force"] : []) + [disk.devicePath])
    }

    /// Smonta una scheda che sta per essere sovrascritta. Spotlight (`mdsync`) e simili tengono occupato un volume appena
    /// inserito e lo lasciano dopo qualche secondo: si riprova, e se ancora non basta si forza, perche' il contenuto sta per
    /// essere cancellato comunque (l'utente ha gia' confermato). `onRetry` riceve una frase da mostrare.
    /// Restituisce `true` se e' stato necessario forzare.
    @discardableResult
    public static func unmountForOverwrite(_ disk: DiskInfo, attempts: Int = 4, delay: TimeInterval = 2,
                                           onRetry: (String) -> Void = { _ in }) throws -> Bool {
        for attempt in 1...max(attempts, 1) {
            do {
                try unmount(disk)
                return false
            } catch {
                let who = dissenter(in: "\(error)").map { "\($0) tiene occupata la scheda" } ?? "la scheda e' occupata"
                if attempt < attempts {
                    onRetry("\(who): riprovo fra \(Int(delay)) s (\(attempt)/\(attempts - 1))")
                    Thread.sleep(forTimeInterval: delay)
                } else {
                    onRetry("\(who): la forzo, tanto verra' sovrascritta")
                }
            }
        }
        try unmount(disk, force: true)
        return true
    }

    public static func mount(_ disk: DiskInfo) throws {
        _ = try DiskEnumerator.runDiskutil(["mountDisk", disk.devicePath])
    }

    public static func eject(_ disk: DiskInfo) throws {
        _ = try DiskEnumerator.runDiskutil(["eject", disk.devicePath])
    }

    /// "Unmount was dissented by PID 4957 (/System/.../mdsync)" -> "mdsync (PID 4957)".
    public static func dissenter(in message: String) -> String? {
        guard let r = message.range(of: #"dissented by PID (\d+) \(([^)]*)\)"#, options: .regularExpression) else { return nil }
        let text = String(message[r])
        let pid = text.split(separator: " ").first { $0.allSatisfy(\.isNumber) }.map(String.init) ?? "?"
        let path = text.drop { $0 != "(" }.dropFirst().dropLast()
        let name = path.split(separator: "/").last.map(String.init) ?? String(path)
        return "\(name) (PID \(pid))"
    }
}
