import Foundation

/// Calcola dove finiscono i dati utili di una scheda leggendo la tabella delle partizioni,
/// cosi' il backup di una SD da 64 GB con 16 GB di partizioni non produce un file da 64 GB.
public enum PartitionLayout {
    public static let sectorSize = 512

    public enum Scheme: Equatable, Sendable {
        case mbr
        case gpt
        case unknown
    }

    public struct Result: Equatable, Sendable {
        public let scheme: Scheme
        /// Byte da copiare partendo dall'inizio del disco.
        public let usedBytes: UInt64
    }

    /// `header` sono i primi byte del disco (almeno 2 settori; per GPT non serve altro).
    /// Con GPT, o se la tabella non e' riconoscibile, si copia tutto il disco: la tabella GPT di
    /// riserva sta in fondo e una copia parziale la perderebbe.
    public static func analyze(header: Data, diskSize: UInt64) -> Result {
        let full = Result(scheme: .unknown, usedBytes: diskSize)
        guard header.count >= 512, header[510] == 0x55, header[511] == 0xAA else { return full }

        var end: UInt64 = 0
        for i in 0..<4 {
            let base = 446 + i * 16
            let type = header[base + 4]
            if type == 0xEE { return Result(scheme: .gpt, usedBytes: diskSize) }
            if type == 0 { continue }
            let start = UInt64(le32(header, base + 8))
            let sectors = UInt64(le32(header, base + 12))
            if sectors == 0 { continue }
            end = max(end, (start + sectors) * UInt64(sectorSize))
        }
        guard end > 0 else { return full }
        // Mai oltre la dimensione del disco: una tabella corrotta non deve far leggere fuori.
        return Result(scheme: .mbr, usedBytes: min(end, diskSize))
    }

    private static func le32(_ d: Data, _ offset: Int) -> UInt32 {
        let s = d.startIndex + offset
        return UInt32(d[s]) | UInt32(d[s + 1]) << 8 | UInt32(d[s + 2]) << 16 | UInt32(d[s + 3]) << 24
    }
}
