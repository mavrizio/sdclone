import XCTest
@testable import SDCore

final class PartitionLayoutTests: XCTestCase {
    /// Settore 0 con le partizioni date come (tipo, settore iniziale, numero di settori).
    private func mbr(_ parts: [(type: UInt8, start: UInt32, sectors: UInt32)], signature: Bool = true) -> Data {
        var d = [UInt8](repeating: 0, count: 512)
        for (i, p) in parts.enumerated() {
            let base = 446 + i * 16
            d[base + 4] = p.type
            for b in 0..<4 {
                d[base + 8 + b] = UInt8((p.start >> (8 * UInt32(b))) & 0xFF)
                d[base + 12 + b] = UInt8((p.sectors >> (8 * UInt32(b))) & 0xFF)
            }
        }
        if signature { d[510] = 0x55; d[511] = 0xAA }
        return Data(d)
    }

    private let disk64: UInt64 = 62_575_000_000

    func testRaspberryPiLayoutStopsAtEndOfLastPartition() {
        // bootfs FAT32 + rootfs Linux, come una Raspberry Pi OS.
        let header = mbr([(0x0C, 8192, 1_048_576), (0x83, 1_056_768, 30_000_000)])
        let r = PartitionLayout.analyze(header: header, diskSize: disk64)
        XCTAssertEqual(r.scheme, .mbr)
        XCTAssertEqual(r.usedBytes, UInt64(1_056_768 + 30_000_000) * 512)
    }

    func testLastPartitionIsTheOneThatEndsFurthest() {
        // Le voci della tabella non sono per forza in ordine di posizione.
        let header = mbr([(0x83, 2_000_000, 1_000_000), (0x0C, 8192, 100_000)])
        XCTAssertEqual(PartitionLayout.analyze(header: header, diskSize: disk64).usedBytes, 3_000_000 * 512)
    }

    func testProtectiveGPTCopiesWholeDisk() {
        let header = mbr([(0xEE, 1, 0xFFFF_FFFF)])
        let r = PartitionLayout.analyze(header: header, diskSize: disk64)
        XCTAssertEqual(r.scheme, .gpt)
        XCTAssertEqual(r.usedBytes, disk64)
    }

    func testMissingSignatureCopiesWholeDisk() {
        let r = PartitionLayout.analyze(header: mbr([(0x83, 2048, 1000)], signature: false), diskSize: disk64)
        XCTAssertEqual(r.scheme, .unknown)
        XCTAssertEqual(r.usedBytes, disk64)
    }

    func testEmptyTableAndShortHeaderCopyWholeDisk() {
        XCTAssertEqual(PartitionLayout.analyze(header: mbr([]), diskSize: disk64).usedBytes, disk64)
        XCTAssertEqual(PartitionLayout.analyze(header: Data(count: 100), diskSize: disk64).usedBytes, disk64)
        XCTAssertEqual(PartitionLayout.analyze(header: Data(), diskSize: disk64).usedBytes, disk64)
    }

    func testCorruptTableNeverExceedsDiskSize() {
        let header = mbr([(0x83, 2048, 0xFFFF_FFF0)])
        XCTAssertEqual(PartitionLayout.analyze(header: header, diskSize: 1_000_000).usedBytes, 1_000_000)
    }
}
