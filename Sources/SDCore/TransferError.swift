import Foundation

public enum TransferError: Error, CustomStringConvertible {
    case cannotOpenSource(String, Int32)
    case cannotOpenTarget(String, Int32)
    case cannotCreateDestination(String, Int32)
    case readFailed(offset: UInt64, errno: Int32)
    case writeFailed(errno: Int32)
    case shortRead(expected: UInt64, got: UInt64)
    case insufficientSpace(needed: UInt64, available: UInt64)
    case imageEmptyOrNotSectorAligned(UInt64)
    case imageTooLarge(image: UInt64, capacity: UInt64)
    case verificationFailed(expected: String, actual: String)
    /// Siamo root ma macOS (TCC) nega comunque l'accesso diretto al disco.
    case accessBlockedByMacOS(String)
    case compressionFailed(String)
    case cancelled

    /// Errore di apertura di un dispositivo: distingue il blocco di macOS da un semplice "serve sudo".
    static func openFailure(_ path: String, _ code: Int32, writing: Bool = false) -> TransferError {
        // Da root un EPERM viene dalla privacy di macOS (TCC): vale per la scheda (/dev/…) e anche per l'immagine in
        // ~/Documents, ~/Desktop, ~/Downloads, che nel ripristino e' la prima cosa che si apre.
        if code == EPERM, geteuid() == 0 { return .accessBlockedByMacOS(path) }
        return writing ? .cannotOpenTarget(path, code) : .cannotOpenSource(path, code)
    }

    public var description: String {
        switch self {
        case .cannotOpenSource(let p, let e): return "impossibile aprire \(p): \(Self.reason(e))"
        case .cannotOpenTarget(let p, let e): return "impossibile aprire \(p) in scrittura: \(Self.reason(e))"
        case .cannotCreateDestination(let p, let e): return "impossibile creare \(p): \(Self.reason(e))"
        case .readFailed(let o, let e): return "errore di lettura al byte \(o): \(Self.reason(e))"
        case .writeFailed(let e): return "errore di scrittura: \(Self.reason(e))"
        case .shortRead(let x, let g): return "la sorgente e' finita prima del previsto (\(g) di \(x) byte)"
        case .insufficientSpace(let n, let a):
            return "spazio insufficiente: servono \(ByteFormat.string(n)), disponibili \(ByteFormat.string(a))"
        case .imageEmptyOrNotSectorAligned(let n):
            return "l'immagine (\(n) byte) e' vuota o non e' un multiplo di \(PartitionLayout.sectorSize) byte"
        case .imageTooLarge(let i, let c):
            return "l'immagine (\(ByteFormat.string(i))) non entra nella SD di destinazione (\(ByteFormat.string(c)))"
        case .verificationFailed(let e, let a):
            return "verifica fallita: i dati scritti non coincidono (attesi \(e.prefix(12))..., letti \(a.prefix(12))...)"
        case .accessBlockedByMacOS(let p):
            return "macOS ha bloccato l'accesso diretto a \(p), anche come amministratore. "
                + "Apri Impostazioni di Sistema > Privacy e sicurezza > Accesso completo al disco, attiva l'app da cui "
                + "lanci il comando (Terminale, Visual Studio Code, iTerm… oppure SD Clone), poi chiudila e riaprila."
        case .compressionFailed(let m): return m
        case .cancelled: return "operazione annullata"
        }
    }

    private static func reason(_ e: Int32) -> String {
        String(cString: strerror(e)) + ((e == EACCES || e == EPERM) && geteuid() != 0 ? " (serve sudo)" : "")
    }
}
