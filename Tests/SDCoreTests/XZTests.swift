import XCTest
import CryptoKit
@testable import SDCore

final class XZTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sdclone-xz-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Immagine da 4 MiB comprimibile: un po' di testo, un po' di rumore, il resto zeri (come una rootfs poco piena).
    private func makeImage(name: String = "card.img") throws -> (url: URL, data: Data) {
        var bytes = [UInt8](repeating: 0, count: 8192 * 512)
        let text = Array("rootfs raspberry pi os /usr/lib/aarch64-linux-gnu\n".utf8)
        for i in 0..<(512 * 1024) { bytes[i] = text[i % text.count] }
        var rng = SystemRandomNumberGenerator()
        for i in (1024 * 1024)..<(1024 * 1024 + 128 * 1024) { bytes[i] = UInt8.random(in: 0...255, using: &rng) }
        let data = Data(bytes)
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        return (url, data)
    }

    private func sha(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    private func xzBinary() -> String? {
        ["/usr/bin/xz", "/opt/homebrew/bin/xz", "/usr/local/bin/xz"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func run(_ exe: String, _ args: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    private func compress(_ image: (url: URL, data: Data), to name: String = "card.img.xz") throws -> (url: URL, result: BackupResult) {
        let out = dir.appendingPathComponent(name)
        let r = try BackupEngine(blockSize: 64 * 1024, xzChunkSize: 256 * 1024).run(source: image.url.path, length: UInt64(image.data.count),
                                                           destination: out, compress: true)
        return (out, r)
    }

    private func restoreToFile(_ image: URL, capacity: UInt64) throws -> (target: URL, result: RestoreResult) {
        let target = dir.appendingPathComponent("target-\(UUID().uuidString).bin")
        try Data(repeating: 0xAA, count: Int(capacity)).write(to: target)
        let r = try RestoreEngine(blockSize: 64 * 1024).run(image: image, target: target.path, targetCapacity: capacity)
        return (target, r)
    }

    // MARK: - Compressione

    func testCompressionShrinksAndKeepsHashOfUncompressedData() throws {
        let img = try makeImage()
        let (out, r) = try compress(img)
        XCTAssertEqual(r.sha256, sha(img.data), "lo SHA256 e' quello dei dati non compressi")
        XCTAssertEqual(r.bytesCopied, UInt64(img.data.count))
        XCTAssertEqual(r.outputBytes, UInt64(try Data(contentsOf: out).count))
        XCTAssertLessThan(r.outputBytes, UInt64(img.data.count) / 4)
        XCTAssertTrue(XZFormat.isXZ(out))
        XCTAssertFalse(XZFormat.isXZ(img.url))
        XCTAssertEqual(try XZFormat.uncompressedSize(of: out), UInt64(img.data.count))
    }

    func testOutputIsAValidXZFileForTheRealXZTool() throws {
        let tool = try XCTUnwrap(xzBinary(), "xz non installato")
        let (out, _) = try compress(try makeImage())
        XCTAssertEqual(try run(tool, ["-t", out.path]), 0, "xz -t deve accettare il file")
    }

    func testParallelOutputIsOneStreamWithManyBlocks() throws {
        let tool = try XCTUnwrap(xzBinary(), "xz non installato")
        let img = try makeImage()
        let (out, r) = try compress(img)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = ["--robot", "--list", out.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        let fields = try XCTUnwrap(text.split(separator: "\n").first { $0.hasPrefix("file") }).split(separator: "\t")
        XCTAssertEqual(Int(fields[1]), 1, "un solo stream, non xz concatenati")
        XCTAssertGreaterThan(Int(fields[2]) ?? 0, 8, "molti blocchi, compressi in parallelo")
        XCTAssertEqual(UInt64(fields[4]), UInt64(img.data.count))
        XCTAssertEqual(r.sha256, sha(img.data))

        // e decomprimendo con l'xz vero si riottengono esattamente i byte originali
        let back = dir.appendingPathComponent("back.img")
        let q = Process()
        q.executableURL = URL(fileURLWithPath: tool)
        q.arguments = ["-dc", out.path]
        FileManager.default.createFile(atPath: back.path, contents: nil)
        q.standardOutput = try FileHandle(forWritingTo: back)
        try q.run()
        q.waitUntilExit()
        XCTAssertEqual(try Data(contentsOf: back), img.data)
    }

    func testEmptyInputStillGivesAValidXZFile() throws {
        let tool = try XCTUnwrap(xzBinary(), "xz non installato")
        let empty = dir.appendingPathComponent("empty.img")
        try Data().write(to: empty)
        let out = dir.appendingPathComponent("empty.img.xz")
        _ = try BackupEngine().run(source: empty.path, length: 0, destination: out, compress: true)
        XCTAssertEqual(try run(tool, ["-t", out.path]), 0)
        XCTAssertEqual(try XZFormat.uncompressedSize(of: out), 0)
    }

    func testRestoreFromXZWritesOriginalBytes() throws {
        let img = try makeImage()
        let (out, packed) = try compress(img)
        let cap = UInt64(img.data.count) + 1024 * 1024
        let (target, r) = try restoreToFile(out, capacity: cap)

        let written = try Data(contentsOf: target)
        XCTAssertEqual(written.prefix(img.data.count), img.data)
        XCTAssertEqual(written.dropFirst(img.data.count), Data(repeating: 0xAA, count: 1024 * 1024), "oltre l'immagine non si tocca nulla")
        XCTAssertEqual(r.sha256, packed.sha256)
        XCTAssertEqual(r.bytesWritten, UInt64(img.data.count))
    }

    func testRestoreRejectsXZLargerThanTargetUsingUncompressedSize() throws {
        let img = try makeImage()
        let (out, _) = try compress(img)
        XCTAssertLessThan(try Data(contentsOf: out).count, 1024 * 1024)   // il file compresso entrerebbe...
        let target = dir.appendingPathComponent("small.bin")
        try Data(count: 1024 * 1024).write(to: target)
        XCTAssertThrowsError(try RestoreEngine().run(image: out, target: target.path, targetCapacity: 1024 * 1024)) { error in
            guard case TransferError.imageTooLarge = error else { return XCTFail("errore inatteso: \(error)") }   // ...ma decompresso no
        }
    }

    func testRestoreReadsXZMadeByTheRealMultiThreadedTool() throws {
        let tool = try XCTUnwrap(xzBinary(), "xz non installato")
        let img = try makeImage()
        let copy = dir.appendingPathComponent("tool.img")
        try img.data.write(to: copy)
        XCTAssertEqual(try run(tool, ["-T0", "-6", "-k", "--block-size=1MiB", copy.path]), 0)
        let packed = copy.appendingPathExtension("xz")

        XCTAssertEqual(try XZFormat.uncompressedSize(of: packed), UInt64(img.data.count))
        let (target, r) = try restoreToFile(packed, capacity: UInt64(img.data.count))
        XCTAssertEqual(try Data(contentsOf: target), img.data)
        XCTAssertEqual(r.sha256, sha(img.data))
    }

    func testConcatenatedXZStreamsAreDecodedAsOne() throws {
        let a = try makeImage(name: "a.img")
        let b = try makeImage(name: "b.img")
        let (xa, _) = try compress(a, to: "a.img.xz")
        let (xb, _) = try compress(b, to: "b.img.xz")
        let joined = dir.appendingPathComponent("joined.img.xz")
        try (Data(contentsOf: xa) + Data(contentsOf: xb)).write(to: joined)

        XCTAssertEqual(try XZFormat.uncompressedSize(of: joined), UInt64(a.data.count + b.data.count))
        let (target, _) = try restoreToFile(joined, capacity: UInt64(a.data.count + b.data.count))
        XCTAssertEqual(try Data(contentsOf: target), a.data + b.data)
    }

    func testTruncatedXZFailsInsteadOfWritingGarbageSilently() throws {
        let (out, _) = try compress(try makeImage())
        let full = try Data(contentsOf: out)
        let cut = dir.appendingPathComponent("cut.img.xz")
        try full.prefix(full.count / 2).write(to: cut)
        XCTAssertThrowsError(try XZFormat.uncompressedSize(of: cut))

        let target = dir.appendingPathComponent("t.bin")
        try Data(count: 8192 * 512).write(to: target)
        XCTAssertThrowsError(try RestoreEngine().run(image: cut, target: target.path, targetCapacity: 8192 * 512))
    }

    func testCompressingAnExistingImageFileWorksWithoutRoot() throws {
        // "Comprimi" in Archivio: la sorgente e' un normale .img, non un dispositivo.
        let img = try makeImage()
        let (out, r) = try compress(img)
        let (target, _) = try restoreToFile(out, capacity: UInt64(img.data.count))
        XCTAssertEqual(sha(try Data(contentsOf: target)), r.sha256)
    }

    func testLibraryListsCompressedImagesWithCleanNames() throws {
        let img = try makeImage(name: "pi.img")
        _ = try compress(img, to: "pi.img.xz")
        let entries = BackupLibrary.entries(in: dir)
        let packed = try XCTUnwrap(entries.first { $0.isCompressed })
        XCTAssertEqual(packed.name, "pi")
        XCTAssertEqual(entries.first { !$0.isCompressed }?.name, "pi")
        XCTAssertTrue(BackupLibrary.newFileName(compressed: true).hasSuffix(".img.xz"))
    }

    func testUnreadableImageReportsAccessErrorNotInvalidImage() throws {
        let (out, _) = try compress(try makeImage())
        chmod(out.path, 0)
        defer { chmod(out.path, 0o644) }
        XCTAssertThrowsError(try RestoreEngine().imageSize(out)) { error in
            if case TransferError.imageEmptyOrNotSectorAligned = error {
                XCTFail("un file illeggibile non deve sembrare un'immagine non valida")
            }
        }
    }
}
