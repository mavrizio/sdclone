import XCTest
@testable import SDCore

/// Prova vera con DiskArbitration: un'immagine FAT collegata senza montarla fa da "scheda".
final class MountBlockerTests: XCTestCase {
    private var dir: URL!
    private var device: String?

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sdclone-mount-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let device { _ = try? run("/usr/bin/hdiutil", ["detach", "/dev/\(device)", "-force"]) }
        try? FileManager.default.removeItem(at: dir)
    }

    @discardableResult
    private func run(_ tool: String, _ args: [String]) throws -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func testMountIsRefusedWhileBlockerIsAliveAndAllowedAfterwards() throws {
        let image = dir.appendingPathComponent("card.dmg").path
        guard try run("/usr/bin/hdiutil", ["create", "-size", "8m", "-fs", "MS-DOS FAT16", "-volname", "SDCTEST", "-layout", "MBRSPUD", image]).status == 0 else {
            throw XCTSkip("hdiutil non disponibile")
        }
        let attach = try run("/usr/bin/hdiutil", ["attach", "-nomount", image])
        guard attach.status == 0, let whole = attach.output.split(whereSeparator: \.isWhitespace).first.map(String.init) else {
            throw XCTSkip("impossibile collegare l'immagine: \(attach.output)")
        }
        device = whole.replacingOccurrences(of: "/dev/", with: "")
        let disk = try XCTUnwrap(device)

        var blocker = MountBlocker(wholeDisk: disk)
        XCTAssertNotNil(blocker)
        // diskutil dice "mounted successfully" anche quando il montaggio e' stato rifiutato: conta solo la tabella vera
        try run("/usr/sbin/diskutil", ["mountDisk", disk])
        XCTAssertFalse(try run("/sbin/mount", []).output.contains("/dev/\(disk)s"), "nessun volume deve risultare montato")

        blocker = nil
        let allowed = try run("/usr/sbin/diskutil", ["mountDisk", disk])
        XCTAssertEqual(allowed.status, 0, allowed.output)
        XCTAssertTrue(try run("/sbin/mount", []).output.contains("/dev/\(disk)s"), "senza blocco il volume si monta")
    }
}
