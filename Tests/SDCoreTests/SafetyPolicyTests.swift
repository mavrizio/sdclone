import XCTest
@testable import SDCore

final class SafetyPolicyTests: XCTestCase {
    private func infoPlist(id: String, size: Int, bus: String, internal isInternal: Bool,
                           removable: Bool, physical: Bool = true, whole: Bool = true,
                           ejectable: Bool = true, systemImage: Bool = false) -> Data {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>DeviceIdentifier</key><string>\(id)</string>
          <key>MediaName</key><string>Test</string>
          <key>BusProtocol</key><string>\(bus)</string>
          <key>TotalSize</key><integer>\(size)</integer>
          <key>DeviceBlockSize</key><integer>512</integer>
          <key>Internal</key><\(isInternal)/>
          <key>RemovableMedia</key><\(removable)/>
          <key>Ejectable</key><\(ejectable)/>
          <key>SystemImage</key><\(systemImage)/>
          <key>WholeDisk</key><\(whole)/>
          <key>VirtualOrPhysical</key><string>\(physical ? "Physical" : "Virtual")</string>
        </dict></plist>
        """.data(using: .utf8)!
    }

    private func disk(_ data: Data) throws -> DiskInfo {
        try XCTUnwrap(DiskEnumerator.parseInfo(data, volumeNames: []))
    }

    func testSDCardIsSelectable() throws {
        let d = try disk(infoPlist(id: "disk4", size: 63_864_569_856, bus: "USB", internal: false, removable: true))
        XCTAssertNil(SafetyPolicy.default.rejection(for: d))
    }

    func testBuiltInSDSlotIsSelectable() throws {
        let d = try disk(infoPlist(id: "disk4", size: 32_010_928_128, bus: "Secure Digital", internal: false, removable: false))
        XCTAssertTrue(SafetyPolicy.default.isSelectable(d))
    }

    func testInternalDiskIsRejected() throws {
        let d = try disk(infoPlist(id: "disk0", size: 500_277_792_768, bus: "Apple Fabric", internal: true, removable: false))
        XCTAssertEqual(SafetyPolicy.default.rejection(for: d), .internalDisk)
    }

    /// Valori reali del lettore SD integrato di un MacBook: Internal=true ma removibile ed espellibile.
    func testBuiltInSDReaderReportingInternalIsSelectable() throws {
        let d = try disk(infoPlist(id: "disk4", size: 62_568_529_920, bus: "Secure Digital", internal: true, removable: true))
        XCTAssertNil(SafetyPolicy.default.rejection(for: d))
    }

    func testInternalRemovableButNotEjectableIsRejected() throws {
        let d = try disk(infoPlist(id: "disk0", size: 16_000_000_000, bus: "USB", internal: true, removable: true, ejectable: false))
        XCTAssertEqual(SafetyPolicy.default.rejection(for: d), .internalDisk)
    }

    func testLargeExternalSSDIsRejected() throws {
        let d = try disk(infoPlist(id: "disk6", size: 2_000_398_934_016, bus: "USB", internal: false, removable: false))
        XCTAssertEqual(SafetyPolicy.default.rejection(for: d), .tooLarge(limit: 512 * 1_000_000_000))
    }

    func testVirtualDiskImageIsRejected() throws {
        let d = try disk(infoPlist(id: "disk9", size: 8_000_000_000, bus: "Disk Image", internal: false, removable: false, physical: false))
        XCTAssertEqual(SafetyPolicy.default.rejection(for: d), .notPhysical)
    }

    func testEmptyCardReaderIsRejected() throws {
        let d = try disk(infoPlist(id: "disk5", size: 0, bus: "USB", internal: false, removable: true))
        XCTAssertEqual(SafetyPolicy.default.rejection(for: d), .zeroSize)
    }

    func testPartitionIsNotReturnedAsWholeDisk() throws {
        let data = infoPlist(id: "disk4s1", size: 1_000_000, bus: "USB", internal: false, removable: true, whole: false)
        XCTAssertNil(try DiskEnumerator.parseInfo(data, volumeNames: []))
    }

    func testMissingInternalFlagDefaultsToInternal() throws {
        let data = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
          <key>DeviceIdentifier</key><string>disk3</string>
          <key>WholeDisk</key><true/>
          <key>TotalSize</key><integer>16000000000</integer>
          <key>VirtualOrPhysical</key><string>Physical</string>
        </dict></plist>
        """.data(using: .utf8)!
        let d = try disk(data)
        XCTAssertEqual(SafetyPolicy.default.rejection(for: d), .internalDisk)
    }

    func testRawDevicePath() throws {
        let d = try disk(infoPlist(id: "disk4", size: 1_000_000_000, bus: "USB", internal: false, removable: true))
        XCTAssertEqual(d.devicePath, "/dev/disk4")
        XCTAssertEqual(d.rawDevicePath, "/dev/rdisk4")
    }
}
