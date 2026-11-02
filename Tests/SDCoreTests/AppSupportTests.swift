import XCTest
@testable import SDCore

/// Parti del motore usate dall'app: stato del lavoro, archivio dei backup, partizioni.
final class AppSupportTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sdclone-app-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - JobStatus

    func testJobStatusRoundTripsThroughFile() throws {
        let url = dir.appendingPathComponent("status.json")
        let status = JobStatus(state: .running, phase: .verifying, bytesDone: 5, bytesTotal: 10,
                               bytesPerSecond: 2.5, secondsRemaining: 2, sha256: "ab", outputPath: "/x.img", message: nil)
        try status.write(to: url)
        XCTAssertEqual(JobStatus.read(from: url), status)
    }

    func testJobStatusReadOfMissingOrCorruptFileIsNil() throws {
        XCTAssertNil(JobStatus.read(from: dir.appendingPathComponent("nope.json")))
        let bad = dir.appendingPathComponent("bad.json")
        try Data("{ non json".utf8).write(to: bad)
        XCTAssertNil(JobStatus.read(from: bad))
    }

    func testJobStatusUpdatingFromProgress() {
        let p = TransferProgress(bytesDone: 50, bytesTotal: 200, bytesPerSecond: 10, secondsRemaining: 15)
        let s = JobStatus(state: .starting, phase: .preparing).updating(p, phase: .copying)
        XCTAssertEqual(s.state, .running)
        XCTAssertEqual(s.phase, .copying)
        XCTAssertEqual(s.fraction, 0.25, accuracy: 0.0001)
        XCTAssertFalse(s.isFinished)
        XCTAssertTrue(JobStatus(state: .failed, phase: .copying).isFinished)
    }

    // MARK: - BackupLibrary

    func testLibraryListsOnlyImagesNewestFirstWithSidecarHash() throws {
        let old = dir.appendingPathComponent("old.img")
        let new = dir.appendingPathComponent("new.img")
        try Data(count: 1024).write(to: old)
        try Data(count: 2048).write(to: new)
        try Data("hello".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        let hash = String(repeating: "ab", count: 32)
        try "\(hash)  new.img\n".write(to: new.appendingPathExtension("sha256"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: old.path)

        let entries = BackupLibrary.entries(in: dir)
        XCTAssertEqual(entries.map(\.name), ["new", "old"])
        XCTAssertEqual(entries[0].sizeBytes, 2048)
        XCTAssertEqual(entries[0].sha256, hash)
        XCTAssertNil(entries[1].sha256)
    }

    func testLibraryIgnoresMalformedHashAndMissingFolder() throws {
        let img = dir.appendingPathComponent("a.img")
        try Data(count: 512).write(to: img)
        try "troppo corto".write(to: img.appendingPathExtension("sha256"), atomically: true, encoding: .utf8)
        XCTAssertNil(BackupLibrary.sha256(forImage: img))
        XCTAssertEqual(BackupLibrary.entries(in: dir.appendingPathComponent("non-esiste")), [])
    }

    func testNewFileNameShape() {
        let name = BackupLibrary.newFileName(date: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(name.hasPrefix("sdclone-"))
        XCTAssertTrue(name.hasSuffix(".img"))
    }

    // MARK: - Partizioni da diskutil

    func testParseListReadsPartitionsOfRaspberryCard() throws {
        let plist: [String: Any] = [
            "WholeDisks": ["disk4"],
            "AllDisksAndPartitions": [[
                "DeviceIdentifier": "disk4",
                "Size": 62_568_529_920,
                "Partitions": [
                    ["DeviceIdentifier": "disk4s1", "Content": "Windows_FAT_32", "Size": 536_870_912, "VolumeName": "bootfs"],
                    ["DeviceIdentifier": "disk4s2", "Content": "Linux", "Size": 15_390_474_240, "VolumeName": "rootfs"],
                ],
            ]],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let parsed = try DiskEnumerator.parseList(data)
        XCTAssertEqual(parsed.ids, ["disk4"])
        XCTAssertEqual(parsed.volumes["disk4"], ["bootfs", "rootfs"])
        let parts = try XCTUnwrap(parsed.partitions["disk4"])
        XCTAssertEqual(parts.map(\.kindLabel), ["FAT32", "Linux"])
        XCTAssertEqual(parts.map(\.sizeBytes), [536_870_912, 15_390_474_240])
    }

    func testEstimatedUsedBytesIsSumOfPartitionsCappedAtDiskSize() {
        func disk(_ size: UInt64, _ parts: [UInt64]) -> DiskInfo {
            DiskInfo(identifier: "disk9", mediaName: "x", busProtocol: "USB", sizeBytes: size, blockSize: 512,
                     isInternal: false, isPhysical: true, isRemovableMedia: true, isEjectable: true, isSystemImage: false,
                     partitions: parts.enumerated().map { PartitionInfo(identifier: "disk9s\($0.offset)", name: "", content: "Linux", sizeBytes: $0.element) })
        }
        XCTAssertEqual(disk(1000, [300, 200]).estimatedUsedBytes, 500)
        XCTAssertEqual(disk(1000, [900, 900]).estimatedUsedBytes, 1000)
        XCTAssertEqual(disk(1000, []).estimatedUsedBytes, 1000, "senza partizioni note si indica il disco intero")
    }

    // MARK: - Smontaggio

    func testDissenterIsReadFromDiskutilMessage() {
        let message = "diskutil ha fallito: Unmount of disk4 failed: at least one volume could not be unmounted\n" +
            "Unmount was dissented by PID 4957 (/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/Metadata.framework/Versions/A/Support/mdsync)\n" +
            "Dissenter parent PPID 1 (/sbin/launchd)\n"
        XCTAssertEqual(DiskControl.dissenter(in: message), "mdsync (PID 4957)")
        XCTAssertNil(DiskControl.dissenter(in: "errore qualsiasi"))
    }
}

