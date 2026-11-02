import Foundation

public enum DiskEnumeratorError: Error, CustomStringConvertible {
    case diskutilFailed(String)
    case malformedPlist(String)

    public var description: String {
        switch self {
        case .diskutilFailed(let m): return "diskutil ha fallito: \(m)"
        case .malformedPlist(let m): return "output di diskutil non valido: \(m)"
        }
    }
}

public struct DiskEnumerator: Sendable {
    public init() {}

    /// Elenca tutti i dischi interi del sistema (la selezione si fa con `SafetyPolicy`).
    public func allDisks() throws -> [DiskInfo] {
        let list = try Self.runDiskutil(["list", "-plist"])
        let (ids, volumes, partitions) = try Self.parseList(list)
        return try ids.compactMap { id in
            let info = try Self.runDiskutil(["info", "-plist", id])
            return try Self.parseInfo(info, volumeNames: volumes[id] ?? [], partitions: partitions[id] ?? [])
        }
    }

    // MARK: - Parsing (puro, testabile con plist di esempio)

    /// Restituisce gli identificatori dei dischi interi, i nomi dei volumi e le partizioni di ciascuno.
    static func parseList(_ data: Data) throws
        -> (ids: [String], volumes: [String: [String]], partitions: [String: [PartitionInfo]]) {
        let root = try plist(data)
        guard let whole = root["WholeDisks"] as? [String] else {
            throw DiskEnumeratorError.malformedPlist("manca WholeDisks")
        }
        var volumes: [String: [String]] = [:]
        var partitions: [String: [PartitionInfo]] = [:]
        for entry in root["AllDisksAndPartitions"] as? [[String: Any]] ?? [] {
            guard let id = entry["DeviceIdentifier"] as? String else { continue }
            var names: [String] = []
            if let v = entry["VolumeName"] as? String, !v.isEmpty { names.append(v) }
            var parts: [PartitionInfo] = []
            for p in entry["Partitions"] as? [[String: Any]] ?? [] {
                let name = (p["VolumeName"] as? String) ?? ""
                if !name.isEmpty { names.append(name) }
                if let pid = p["DeviceIdentifier"] as? String {
                    parts.append(PartitionInfo(identifier: pid, name: name,
                                               content: (p["Content"] as? String) ?? "",
                                               sizeBytes: (p["Size"] as? NSNumber)?.uint64Value ?? 0))
                }
            }
            volumes[id] = names
            partitions[id] = parts
        }
        return (whole, volumes, partitions)
    }

    /// Converte l'output di `diskutil info -plist` in `DiskInfo`. Nil se non e' un disco intero.
    static func parseInfo(_ data: Data, volumeNames: [String], partitions: [PartitionInfo] = []) throws -> DiskInfo? {
        let d = try plist(data)
        guard let id = d["DeviceIdentifier"] as? String else {
            throw DiskEnumeratorError.malformedPlist("manca DeviceIdentifier")
        }
        guard d["WholeDisk"] as? Bool == true else { return nil }
        let size = (d["TotalSize"] as? NSNumber ?? d["Size"] as? NSNumber)?.uint64Value ?? 0
        return DiskInfo(
            identifier: id,
            mediaName: (d["MediaName"] as? String) ?? (d["IORegistryEntryName"] as? String) ?? "Sconosciuto",
            busProtocol: (d["BusProtocol"] as? String) ?? "",
            sizeBytes: size,
            blockSize: (d["DeviceBlockSize"] as? Int) ?? 512,
            isInternal: (d["Internal"] as? Bool) ?? true,           // nel dubbio: interno = non toccare
            isPhysical: (d["VirtualOrPhysical"] as? String) == "Physical",
            isRemovableMedia: (d["RemovableMedia"] as? Bool) ?? false,
            isEjectable: (d["Ejectable"] as? Bool) ?? false,
            isSystemImage: (d["SystemImage"] as? Bool) ?? false,
            volumeNames: volumeNames,
            partitions: partitions
        )
    }

    private static func plist(_ data: Data) throws -> [String: Any] {
        guard let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any] else {
            throw DiskEnumeratorError.malformedPlist("non e' un dizionario")
        }
        return dict
    }

    // MARK: - Esecuzione di diskutil

    static func runDiskutil(_ args: [String]) throws -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        // Legge prima di waitUntilExit per non bloccarsi se il buffer della pipe si riempie.
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw DiskEnumeratorError.diskutilFailed(String(decoding: errData, as: UTF8.self))
        }
        return data
    }
}
