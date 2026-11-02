import Foundation

/// Una partizione di un disco, per mostrare com'e' fatta la scheda.
public struct PartitionInfo: Equatable, Sendable, Identifiable {
    public let identifier: String        // "disk4s1"
    public let name: String              // nome del volume, puo' essere vuoto
    public let content: String           // "Windows_FAT_32", "Linux", ...
    public let sizeBytes: UInt64

    public var id: String { identifier }

    public init(identifier: String, name: String, content: String, sizeBytes: UInt64) {
        self.identifier = identifier
        self.name = name
        self.content = content
        self.sizeBytes = sizeBytes
    }

    /// Nome leggibile del tipo di contenuto.
    public var kindLabel: String {
        switch content {
        case "Windows_FAT_32": return "FAT32"
        case "Windows_FAT_16": return "FAT16"
        case "Windows_NTFS": return "NTFS"
        case "Linux": return "Linux"
        case "Apple_APFS": return "APFS"
        case "Apple_HFS": return "HFS+"
        case "DOS_FAT_32": return "FAT32"
        case "": return "—"
        default: return content
        }
    }
}

/// Un disco intero (non una partizione) come lo vede `diskutil`.
public struct DiskInfo: Equatable, Sendable {
    public let identifier: String        // "disk6"
    public let mediaName: String         // "2115", "SD/MMC", ...
    public let busProtocol: String       // "USB", "Secure Digital", ...
    public let sizeBytes: UInt64
    public let blockSize: Int
    public let isInternal: Bool
    public let isPhysical: Bool
    public let isRemovableMedia: Bool
    public let isEjectable: Bool
    public let isSystemImage: Bool
    public let volumeNames: [String]
    public let partitions: [PartitionInfo]

    public init(identifier: String, mediaName: String, busProtocol: String, sizeBytes: UInt64,
                blockSize: Int, isInternal: Bool, isPhysical: Bool, isRemovableMedia: Bool,
                isEjectable: Bool, isSystemImage: Bool, volumeNames: [String] = [],
                partitions: [PartitionInfo] = []) {
        self.identifier = identifier
        self.mediaName = mediaName
        self.busProtocol = busProtocol
        self.sizeBytes = sizeBytes
        self.blockSize = blockSize
        self.isInternal = isInternal
        self.isPhysical = isPhysical
        self.isRemovableMedia = isRemovableMedia
        self.isEjectable = isEjectable
        self.isSystemImage = isSystemImage
        self.volumeNames = volumeNames
        self.partitions = partitions
    }

    /// Stima di quanto verra' copiato da un backup: la somma delle partizioni (la misura esatta,
    /// dalla tabella MBR, richiede root). Senza partizioni note si indica l'intero disco.
    public var estimatedUsedBytes: UInt64 {
        let sum = partitions.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        return sum == 0 ? sizeBytes : min(sizeBytes, sum)
    }

    /// Nodo a blocchi ("/dev/disk6").
    public var devicePath: String { "/dev/\(identifier)" }
    /// Nodo raw, molto piu' veloce per letture/scritture sequenziali ("/dev/rdisk6").
    public var rawDevicePath: String { "/dev/r\(identifier)" }
}
