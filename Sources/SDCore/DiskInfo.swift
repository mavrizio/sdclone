import Foundation

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

    public init(identifier: String, mediaName: String, busProtocol: String, sizeBytes: UInt64,
                blockSize: Int, isInternal: Bool, isPhysical: Bool, isRemovableMedia: Bool,
                isEjectable: Bool, isSystemImage: Bool, volumeNames: [String] = []) {
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
    }

    /// Nodo a blocchi ("/dev/disk6").
    public var devicePath: String { "/dev/\(identifier)" }
    /// Nodo raw, molto piu' veloce per letture/scritture sequenziali ("/dev/rdisk6").
    public var rawDevicePath: String { "/dev/r\(identifier)" }
}
