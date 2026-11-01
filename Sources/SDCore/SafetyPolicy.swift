import Foundation

/// Perche' un disco non puo' essere scelto come sorgente/destinazione.
public enum DiskRejection: Equatable, Sendable {
    case internalDisk
    case notPhysical
    case systemImage
    case tooLarge(limit: UInt64)
    case zeroSize

    public var message: String {
        switch self {
        case .internalDisk: return "disco interno del Mac"
        case .notPhysical: return "disco virtuale / immagine montata"
        case .systemImage: return "immagine di sistema"
        case .tooLarge(let limit):
            return "troppo grande per una SD (> \(ByteFormat.string(limit))): sembra un disco esterno"
        case .zeroSize: return "nessun supporto inserito"
        }
    }
}

/// Regola di sicurezza: decide quali dischi sono candidati validi.
/// E' l'unico punto in cui si decide cosa e' "una SD"; ogni scrittura deve passare da qui.
public struct SafetyPolicy: Sendable {
    /// Oltre questa dimensione un disco non removibile e' considerato un disco esterno, non una SD.
    public var maxNonRemovableSize: UInt64

    public init(maxNonRemovableSize: UInt64 = 512 * 1_000_000_000) {
        self.maxNonRemovableSize = maxNonRemovableSize
    }

    public static let `default` = SafetyPolicy()

    public func rejection(for disk: DiskInfo) -> DiskRejection? {
        // Il lettore SD integrato del Mac si dichiara "Internal", ma e' removibile ed espellibile;
        // gli SSD di sistema non lo sono mai. Un disco interno passa solo con entrambi i flag.
        if disk.isInternal && !(disk.isRemovableMedia && disk.isEjectable) { return .internalDisk }
        if !disk.isPhysical { return .notPhysical }
        if disk.isSystemImage { return .systemImage }
        if disk.sizeBytes == 0 { return .zeroSize }
        let looksLikeSD = disk.isRemovableMedia || disk.busProtocol.lowercased().contains("secure digital")
        if !looksLikeSD && disk.sizeBytes > maxNonRemovableSize {
            return .tooLarge(limit: maxNonRemovableSize)
        }
        return nil
    }

    public func isSelectable(_ disk: DiskInfo) -> Bool { rejection(for: disk) == nil }
}
