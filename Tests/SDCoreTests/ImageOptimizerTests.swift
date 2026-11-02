import XCTest
import CryptoKit
@testable import SDCore

final class ImageOptimizerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sdclone-opt-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Parti senza strumenti esterni

    private func mbr(_ entries: [(type: UInt8, start: UInt32, count: UInt32)]) -> [UInt8] {
        var h = [UInt8](repeating: 0, count: 512)
        for (i, e) in entries.enumerated() {
            let b = 446 + i * 16
            h[b + 4] = e.type
            for k in 0..<4 {
                h[b + 8 + k] = UInt8(truncatingIfNeeded: e.start >> (8 * UInt32(k)))
                h[b + 12 + k] = UInt8(truncatingIfNeeded: e.count >> (8 * UInt32(k)))
            }
        }
        h[510] = 0x55; h[511] = 0xAA
        return h
    }

    func testMBRFindsLinuxRootAndPatchesItsSize() throws {
        var h = mbr([(0x0C, 8192, 1_048_576), (0x83, 1_056_768, 30_000_000)])
        let parts = try MBR.partitions(Data(h))
        let root = try MBR.optimizableRoot(parts, imageBytes: 32_000_000_000)
        XCTAssertEqual(root.number, 2)
        XCTAssertEqual(root.startByte, 1_056_768 * 512)
        try MBR.setSectors(&h, partition: 2, sectors: 12_345_600)
        XCTAssertEqual(try MBR.partitions(Data(h))[1].sectors, 12_345_600)
        XCTAssertEqual(try MBR.partitions(Data(h))[0].sectors, 1_048_576, "le altre voci non cambiano")
    }

    func testMBRRejectsWhatItCannotHandle() {
        XCTAssertThrowsError(try MBR.partitions(Data(count: 512)), "senza firma 55AA")
        XCTAssertThrowsError(try MBR.partitions(Data(mbr([(0xEE, 1, 100)]))), "GPT")
        XCTAssertThrowsError(try MBR.optimizableRoot(try MBR.partitions(Data(mbr([(0x83, 8192, 8192), (0x0C, 16384, 8192)]))),
                                                     imageBytes: 1 << 30), "ultima partizione FAT")
        XCTAssertThrowsError(try MBR.optimizableRoot(try MBR.partitions(Data(mbr([(0x0C, 8192, 8192), (0x83, 16384, 8192)]))),
                                                     imageBytes: 16384 * 512 + 100), "immagine troncata")
    }

    func testToolOutputParsing() {
        XCTAssertEqual(E2fsTools.filesystemBytes(fromResizeOutput: "Resizing...\nThe filesystem on part.img is now 1514496 (4k) blocks long.\n"),
                       1_514_496 * 4096)
        XCTAssertEqual(E2fsTools.filesystemBytes(fromResizeOutput: "The filesystem is already 16384 (1k) blocks long.  Nothing to do!"),
                       16384 * 1024)
        XCTAssertNil(E2fsTools.filesystemBytes(fromResizeOutput: "boh"))
        let list = "debugfs 1.47.2\n/2/040755/0/0/.//\n/12/040700/1000/1000/pi//\n/13/100600/1000/1000/.bash_history/89/\n"
        XCTAssertEqual(E2fsTools.parseList(list), [.init(name: ".", isDirectory: true), .init(name: "pi", isDirectory: true),
                                                    .init(name: ".bash_history", isDirectory: false)])
    }

    func testPlannedNamesNeverReuseExistingFiles() throws {
        let img = dir.appendingPathComponent("Golden.img.xz")
        let opts = ImageOptimizer.Options(shrink: true, clean: false, compress: true, keepUncompressed: true)
        var p = ImageOptimizer.plannedOutputs(for: img, options: opts, in: dir)
        XCTAssertEqual(p.image?.lastPathComponent, "Golden.min.img")
        XCTAssertEqual(p.xz?.lastPathComponent, "Golden.min.img.xz")
        try Data().write(to: dir.appendingPathComponent("Golden.min.img.xz.sha256"))
        p = ImageOptimizer.plannedOutputs(for: img, options: opts, in: dir)
        XCTAssertEqual(p.xz?.lastPathComponent, "Golden.min 2.img.xz")
    }

    // MARK: - Prova completa con un vero ext4 (serve e2fsprogs)

    private struct Fixture {
        let image: URL
        let data: Data
        let notes: Data
        let headerSectors: UInt32 = 8192
        let rootSectors: UInt32 = 131_072   // 64 MiB
    }

    private func tools() throws -> E2fsTools {
        do { return try E2fsTools.locate() } catch { throw XCTSkip("e2fsprogs non installato") }
    }

    /// Immagine "Raspberry" finta: MBR + boot FAT finta + ext4 da 64 MiB con dati, appunti e cronologie.
    private func makeFixture(_ t: E2fsTools) throws -> Fixture {
        let root = dir.appendingPathComponent("root.fs")
        FileManager.default.createFile(atPath: root.path, contents: nil)
        let fx = Fixture(image: dir.appendingPathComponent("Pi.img"),
                         data: Data((0..<3_000_000).map { _ in UInt8.random(in: 0...255) }),
                         notes: Data("da tenere\n".utf8))
        XCTAssertEqual(truncate(root.path, off_t(fx.rootSectors) * 512), 0)
        let mke2fs = t.directory.appendingPathComponent("mke2fs").path
        XCTAssertEqual(try t.run(mke2fs, ["-q", "-F", "-t", "ext4", root.path], isCancelled: { false }).code, 0)

        let files = ["data.bin": fx.data, "notes.txt": fx.notes, "hist": Data("ls\nsudo reboot\n".utf8)]
        for (name, content) in files { try content.write(to: dir.appendingPathComponent(name)) }
        let script = """
        mkdir home
        mkdir home/pi
        mkdir root
        cd /home/pi
        write \(dir.appendingPathComponent("data.bin").path) data.bin
        write \(dir.appendingPathComponent("notes.txt").path) notes.txt
        write \(dir.appendingPathComponent("hist").path) .bash_history
        cd /root
        write \(dir.appendingPathComponent("hist").path) .python_history

        """
        let scriptURL = dir.appendingPathComponent("populate.txt")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(try t.run(t.debugfs, ["-w", "-f", scriptURL.path, root.path], isCancelled: { false }).code, 0)

        var image = Data(mbr([(0x0C, 2048, fx.headerSectors - 2048), (0x83, fx.headerSectors, fx.rootSectors)]))
        image.append(Data((0..<(Int(fx.headerSectors) * 512 - 512)).map { UInt8(truncatingIfNeeded: $0 &* 31) }))
        image.append(try Data(contentsOf: root))
        try image.write(to: fx.image)
        return fx
    }

    private func sha(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private func cat(_ t: E2fsTools, _ image: URL, offset: UInt64, _ path: String) throws -> Data {
        let out = dir.appendingPathComponent("dump-\(UUID().uuidString)")
        _ = try t.run(t.debugfs, ["-R", "dump \(path) \(out.path)", "\(image.path)?offset=\(offset)"], isCancelled: { false })
        return (try? Data(contentsOf: out)) ?? Data()
    }

    func testShrinkCleanCompressProducesSmallerVerifiedImageAndLeavesOriginalAlone() throws {
        let t = try tools()
        let fx = try makeFixture(t)
        let originalSHA = try sha(fx.image)
        let analysis = try ImageOptimizer.analyze(fx.image, tools: t)
        XCTAssertEqual(analysis.root.number, 2)
        let estimate = try XCTUnwrap(analysis.estimatedShrunkBytes)
        XCTAssertLessThan(estimate, analysis.imageBytes)

        var steps: [ImageOptimizer.Step] = []
        let opts = ImageOptimizer.Options(shrink: true, clean: true, compress: true, keepUncompressed: true)
        let r = try ImageOptimizer(blockSize: 1 << 20).run(image: fx.image, options: opts, tools: t,
                                                          progress: { if steps.last != $0.step { steps.append($0.step) } })

        XCTAssertEqual(steps, [.extracting, .checking, .cleaning, .shrinking, .assembling, .verifying, .compressing])
        XCTAssertEqual(try sha(fx.image), originalSHA, "l'originale non deve cambiare")
        XCTAssertEqual(Set(r.removedFiles), ["/home/pi/.bash_history", "/root/.python_history"])

        let img = dir.appendingPathComponent("Pi.min.img"), xz = dir.appendingPathComponent("Pi.min.img.xz")
        XCTAssertEqual(r.output, xz)
        XCTAssertEqual(r.files, [xz, img])
        XCTAssertLessThan(r.imageBytes, analysis.imageBytes)
        XCTAssertEqual(try BlockIO.fileSize(img.path), r.imageBytes)
        XCTAssertEqual(try sha(img), r.sha256)
        let perms = try FileManager.default.attributesOfItem(atPath: img.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o644, "come gli altri backup, non solo per il proprietario")
        XCTAssertEqual(BackupLibrary.sha256(forImage: img), r.sha256)
        XCTAssertEqual(BackupLibrary.sha256(forImage: xz), r.sha256)

        // Il .xz si decomprime nella stessa immagine.
        let reader = try XZFileReader(path: xz.path)
        var buf = [UInt8](repeating: 0, count: Int(r.imageBytes) + 512)
        XCTAssertEqual(try reader.readFully(&buf, buf.count), Int(r.imageBytes))
        XCTAssertEqual(SHA256.hash(data: Data(buf[0..<Int(r.imageBytes)])).map { String(format: "%02x", $0) }.joined(), r.sha256)

        // Tabella aggiornata, boot identico, filesystem pulito con i dati e senza cronologie.
        let out = try Data(contentsOf: img)
        let parts = try MBR.partitions(out)
        XCTAssertEqual(parts[1].endByte, r.imageBytes)
        let original = try Data(contentsOf: fx.image)
        XCTAssertEqual(out[512..<(Int(fx.headerSectors) * 512)], original[512..<(Int(fx.headerSectors) * 512)])
        let offset = parts[1].startByte
        XCTAssertNoThrow(try t.checkReadOnly(img.path, offset: offset, isCancelled: { false }))
        XCTAssertEqual(try cat(t, img, offset: offset, "/home/pi/data.bin"), fx.data)
        XCTAssertEqual(try cat(t, img, offset: offset, "/home/pi/notes.txt"), fx.notes)
        XCTAssertEqual(try t.listDirectory("/home/pi", in: "\(img.path)?offset=\(offset)", isCancelled: { false }).map(\.name).sorted(),
                       [".", "..", "data.bin", "lost+found", "notes.txt"].filter { $0 != "lost+found" })

        // Una seconda volta non sovrascrive: nuovi nomi.
        let again = try ImageOptimizer(blockSize: 1 << 20).run(image: fx.image, options: opts, tools: t)
        XCTAssertEqual(again.output.lastPathComponent, "Pi.min 2.img.xz")
    }

    func testShrinkWorksFromCompressedImageToo() throws {
        let t = try tools()
        let fx = try makeFixture(t)
        let packed = dir.appendingPathComponent("Pi.img.xz")
        let size = try BlockIO.fileSize(fx.image.path)
        _ = try BackupEngine(blockSize: 1 << 20).run(source: fx.image.path, length: size, destination: packed, compress: true)
        try FileManager.default.removeItem(at: fx.image)

        let analysis = try ImageOptimizer.analyze(packed, tools: t)
        XCTAssertTrue(analysis.isCompressed)
        XCTAssertNil(analysis.minimumRootBytes, "senza estrarre non si stima")

        let r = try ImageOptimizer(blockSize: 1 << 20).run(image: packed, options: .init(shrink: true, compress: false), tools: t)
        XCTAssertEqual(r.output.lastPathComponent, "Pi.min.img")
        XCTAssertLessThan(r.imageBytes, size)
        XCTAssertNil(r.compressedBytes)
        XCTAssertNoThrow(try t.checkReadOnly(r.output.path, offset: UInt64(fx.headerSectors) * 512, isCancelled: { false }))
        XCTAssertEqual(try cat(t, r.output, offset: UInt64(fx.headerSectors) * 512, "/home/pi/.bash_history"),
                       Data("ls\nsudo reboot\n".utf8), "senza pulizia le cronologie restano")
    }

    func testCancelLeavesNothingBehind() throws {
        let t = try tools()
        let fx = try makeFixture(t)
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
        var calls = 0
        XCTAssertThrowsError(try ImageOptimizer(blockSize: 1 << 20).run(
            image: fx.image, options: .init(shrink: true, clean: true, compress: true), tools: t,
            progress: { _ in calls += 1 }, isCancelled: { calls > 3 })) { error in
            guard case TransferError.cancelled = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: dir.path)), before)
    }
}
