import Foundation
import SDCore

/// Dati finti per vedere l'interfaccia senza una SD e senza password (`SDCLONE_DEMO=1`).
enum DemoData {
    static let disks: [DiskInfo] = [
        DiskInfo(identifier: "disk4", mediaName: "Built In SDXC Reader", busProtocol: "Secure Digital",
                 sizeBytes: 62_568_529_920, blockSize: 512, isInternal: true, isPhysical: true,
                 isRemovableMedia: true, isEjectable: true, isSystemImage: false,
                 volumeNames: ["bootfs", "rootfs"],
                 partitions: [
                    PartitionInfo(identifier: "disk4s1", name: "bootfs", content: "Windows_FAT_32", sizeBytes: 536_870_912),
                    PartitionInfo(identifier: "disk4s2", name: "rootfs", content: "Linux", sizeBytes: 15_390_474_240),
                 ]),
        DiskInfo(identifier: "disk7", mediaName: "Mass Storage Device", busProtocol: "USB",
                 sizeBytes: 31_914_983_424, blockSize: 512, isInternal: false, isPhysical: true,
                 isRemovableMedia: true, isEjectable: true, isSystemImage: false,
                 volumeNames: ["CGSLIM"],
                 partitions: [
                    PartitionInfo(identifier: "disk7s1", name: "CGSLIM", content: "Windows_FAT_32", sizeBytes: 8_589_934_592),
                 ]),
    ]

    static func library(in folder: URL) -> [BackupEntry] {
        let now = Date()
        func entry(_ name: String, gb: Double, daysAgo: Double, sha: Bool = true, packed: Double? = nil) -> BackupEntry {
            let raw = UInt64(gb * 1_000_000_000) / 512 * 512   // come un'immagine vera: multipla del settore
            return BackupEntry(url: folder.appendingPathComponent(name + (packed == nil ? ".img" : ".img.xz")),
                               sizeBytes: packed.map { UInt64($0 * 1_000_000_000) } ?? raw,
                               date: now.addingTimeInterval(-daysAgo * 86_400),
                               sha256: sha ? String(repeating: "9f3a", count: 16) : nil,
                               isCompressed: packed != nil,
                               uncompressedBytes: packed == nil ? nil : raw)
        }
        return [
            entry("RaspberryPi-20261101-1534", gb: 15.93, daysAgo: 0.1),
            entry("RaspberryPi-20261029-0818", gb: 15.93, daysAgo: 3, packed: 3.4),
            entry("CGSLIM-golden-v2", gb: 8.59, daysAgo: 6),
            entry("RaspberryPi-20260918-0912", gb: 15.93, daysAgo: 44),
            entry("test-vecchio", gb: 3.2, daysAgo: 120, sha: false),
        ]
    }

    /// Analisi finta di un'immagine dell'Archivio demo: boot da 512 MiB, Linux fino in fondo, 4,1 GB usati.
    static func analysis(for entry: BackupEntry?) -> ImageAnalysis {
        let bytes = entry.map { $0.uncompressedBytes ?? $0.sizeBytes } ?? 15_931_539_456
        let start: UInt64 = 1_056_768
        let boot = MBRPartition(number: 1, type: 0x0C, startSector: 8192, sectors: 1_048_576)
        let root = MBRPartition(number: 2, type: 0x83, startSector: start, sectors: bytes / 512 - start)
        let compressed = entry?.isCompressed ?? false
        return ImageAnalysis(imageBytes: bytes, isCompressed: compressed, partitions: [boot, root], root: root,
                             minimumRootBytes: compressed ? nil : 5_700_000_000)
    }
}
