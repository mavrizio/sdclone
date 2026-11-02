import XCTest
import CryptoKit
@testable import SDCore

/// Prova backup e ripristino su file normali: nessun test tocca un disco vero.
final class TransferEngineTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sdclone-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// "SD" finta da 4 MiB: tabella MBR con una sola partizione da 1 MiB + dati pseudo-casuali.
    private func makeFakeCard(totalSectors: Int = 8192, partitionSectors: UInt32 = 2048) throws -> (url: URL, data: Data) {
        var bytes = [UInt8](repeating: 0, count: totalSectors * 512)
        var rng = SystemRandomNumberGenerator()
        for i in 0..<bytes.count { bytes[i] = UInt8.random(in: 0...255, using: &rng) }
        for i in 446..<512 { bytes[i] = 0 }
        let base = 446
        bytes[base + 4] = 0x83
        bytes[base + 8] = 0; bytes[base + 9] = 0; bytes[base + 10] = 0; bytes[base + 11] = 0   // parte dal settore 0
        for b in 0..<4 { bytes[base + 12 + b] = UInt8((partitionSectors >> (8 * UInt32(b))) & 0xFF) }
        bytes[510] = 0x55; bytes[511] = 0xAA
        let data = Data(bytes)
        let url = dir.appendingPathComponent("card.bin")
        try data.write(to: url)
        return (url, data)
    }

    private func sha(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    // MARK: - Backup

    func testBackupCopiesOnlyUsedPartAndReportsHash() throws {
        let card = try makeFakeCard()
        let engine = BackupEngine(blockSize: 64 * 1024)
        let layout = try engine.layout(of: card.url.path, diskSize: UInt64(card.data.count))
        XCTAssertEqual(layout.usedBytes, 2048 * 512)

        let out = dir.appendingPathComponent("backup.img")
        var last: TransferProgress?
        let r = try engine.run(source: card.url.path, length: layout.usedBytes, destination: out,
                               progress: { last = $0 })
        let written = try Data(contentsOf: out)
        XCTAssertEqual(written, card.data.prefix(Int(layout.usedBytes)))
        XCTAssertEqual(r.bytesCopied, layout.usedBytes)
        XCTAssertEqual(r.sha256, sha(written))
        XCTAssertEqual(last?.fraction, 1)
    }

    func testBackupCancelledLeavesNoPartialFile() throws {
        let card = try makeFakeCard()
        let out = dir.appendingPathComponent("backup.img")
        var calls = 0
        XCTAssertThrowsError(try BackupEngine(blockSize: 4096).run(
            source: card.url.path, length: UInt64(card.data.count), destination: out,
            isCancelled: { calls += 1; return calls > 3 })) { error in
            guard case TransferError.cancelled = error else { return XCTFail("errore inatteso: \(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }

    func testBackupFailsAndCleansUpWhenSourceIsShorterThanExpected() throws {
        let card = try makeFakeCard()
        let out = dir.appendingPathComponent("backup.img")
        XCTAssertThrowsError(try BackupEngine(blockSize: 4096).run(
            source: card.url.path, length: UInt64(card.data.count) + 4096, destination: out)) { error in
            guard case TransferError.shortRead = error else { return XCTFail("errore inatteso: \(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }

    func testBackupOfMissingSourceFails() {
        XCTAssertThrowsError(try BackupEngine().run(source: dir.appendingPathComponent("nope").path,
                                                    length: 512, destination: dir.appendingPathComponent("o.img")))
    }

    // MARK: - Ripristino

    func testRestoreWritesImageVerifiesAndLeavesRestOfTargetUntouched() throws {
        let card = try makeFakeCard()
        let imageURL = dir.appendingPathComponent("backup.img")
        let backup = try BackupEngine(blockSize: 8192).run(source: card.url.path, length: 2048 * 512, destination: imageURL)

        // Destinazione piu' grande, piena di 0xAA: oltre l'immagine non deve cambiare nulla.
        let target = dir.appendingPathComponent("target.bin")
        try Data(repeating: 0xAA, count: 4 * 1024 * 1024).write(to: target)

        var phases = Set<String>()
        let r = try RestoreEngine(blockSize: 8192).run(
            image: imageURL, target: target.path, targetCapacity: 4 * 1024 * 1024,
            progress: { phases.insert($0.phase == .writing ? "w" : "v") })

        let result = try Data(contentsOf: target)
        XCTAssertEqual(result.prefix(2048 * 512), try Data(contentsOf: imageURL))
        XCTAssertEqual(result.dropFirst(2048 * 512), Data(repeating: 0xAA, count: 4 * 1024 * 1024 - 2048 * 512))
        XCTAssertEqual(r.sha256, backup.sha256)
        XCTAssertEqual(phases, ["w", "v"])
    }

    func testRestoreRejectsImageLargerThanTarget() throws {
        let card = try makeFakeCard()
        let target = dir.appendingPathComponent("target.bin")
        try Data(count: 1024).write(to: target)
        XCTAssertThrowsError(try RestoreEngine().run(image: card.url, target: target.path, targetCapacity: 1024)) { error in
            guard case TransferError.imageTooLarge = error else { return XCTFail("errore inatteso: \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: target), Data(count: 1024), "il target non va toccato")
    }

    func testRestoreRejectsImageNotMultipleOfSector() throws {
        let image = dir.appendingPathComponent("odd.img")
        try Data(count: 1000).write(to: image)
        let target = dir.appendingPathComponent("target.bin")
        try Data(count: 4096).write(to: target)
        XCTAssertThrowsError(try RestoreEngine().run(image: image, target: target.path, targetCapacity: 4096)) { error in
            guard case TransferError.imageEmptyOrNotSectorAligned = error else { return XCTFail("errore inatteso: \(error)") }
        }
    }

    func testRestoreDoesNotCreateMissingTarget() throws {
        let card = try makeFakeCard()
        let target = dir.appendingPathComponent("does-not-exist")
        XCTAssertThrowsError(try RestoreEngine().run(image: card.url, target: target.path,
                                                     targetCapacity: UInt64(card.data.count))) { error in
            guard case TransferError.cannotOpenTarget = error else { return XCTFail("errore inatteso: \(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }
}
