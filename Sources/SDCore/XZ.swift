import Foundation
import Compression

/// Compressione e decompressione `.xz` in streaming con il framework Compression di Apple (nessuna
/// dipendenza esterna). Il file prodotto e' un normale `.xz`: lo leggono `xz`, 7-Zip e Raspberry Pi Imager.

/// Lettore sequenziale di un'immagine, grezza o compressa: il ripristino non distingue.
protocol SequentialReader: AnyObject {
    /// Legge fino a `count` byte; restituisce meno di `count` solo alla fine dei dati.
    func readFully(_ buffer: inout [UInt8], _ count: Int) throws -> Int
}

final class RawFileReader: SequentialReader {
    private let fd: Int32
    private var offset: UInt64 = 0

    init(path: String) throws {
        fd = open(path, O_RDONLY)
        guard fd >= 0 else { throw TransferError.openFailure(path, errno) }
        _ = fcntl(fd, F_NOCACHE, 1)
    }

    deinit { close(fd) }

    func readFully(_ buffer: inout [UInt8], _ count: Int) throws -> Int {
        let n = try BlockIO.readFully(fd, &buffer, count, offset: offset)
        offset += UInt64(n)
        return n
    }
}

// MARK: - Compressione

final class XZEncoder {
    private var stream: compression_stream
    private var out = [UInt8](repeating: 0, count: 1 << 20)

    init() throws {
        stream = compression_stream(dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!, dst_size: 0,
                                    src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_LZMA) == COMPRESSION_STATUS_OK else {
            throw TransferError.compressionFailed("impossibile avviare la compressione")
        }
    }

    deinit { compression_stream_destroy(&stream) }

    /// Comprime tutto `input` in un unico stream .xz completo.
    func encodeAll(_ input: [UInt8]) throws -> [UInt8] {
        var result = [UInt8]()
        result.reserveCapacity(input.count / 3)
        try append(input, count: input.count) { result.append(contentsOf: $0) }
        try finish { result.append(contentsOf: $0) }
        return result
    }

    /// Comprime `count` byte di `buffer`; i byte compressi pronti escono da `sink`.
    func append(_ buffer: [UInt8], count: Int, sink: (UnsafeBufferPointer<UInt8>) throws -> Void) throws {
        try buffer.withUnsafeBufferPointer { p in
            stream.src_ptr = p.baseAddress!
            stream.src_size = count
            try drain(flags: 0, sink: sink)
        }
    }

    func finish(sink: (UnsafeBufferPointer<UInt8>) throws -> Void) throws {
        stream.src_size = 0
        try drain(flags: Int32(COMPRESSION_STREAM_FINALIZE.rawValue), sink: sink)
    }

    private func drain(flags: Int32, sink: (UnsafeBufferPointer<UInt8>) throws -> Void) throws {
        while true {
            let status = out.withUnsafeMutableBufferPointer { p -> compression_status in
                stream.dst_ptr = p.baseAddress!
                stream.dst_size = p.count
                return compression_stream_process(&stream, flags)
            }
            let produced = out.count - stream.dst_size
            if produced > 0 {
                try out.withUnsafeBufferPointer { try sink(UnsafeBufferPointer(rebasing: $0[0..<produced])) }
            }
            if status == COMPRESSION_STATUS_ERROR { throw TransferError.compressionFailed("errore durante la compressione") }
            if status == COMPRESSION_STATUS_END { return }
            // Input consumato e buffer di uscita non pieno: per ora non c'e' altro da prelevare.
            if flags == 0 && stream.src_size == 0 && stream.dst_size > 0 { return }
        }
    }
}

// MARK: - Decompressione

final class XZFileReader: SequentialReader {
    private let fd: Int32
    private let path: String
    private var stream: compression_stream
    private let inCapacity = 1 << 20
    private let inBuffer: UnsafeMutablePointer<UInt8>
    private var inputEOF = false
    private var finished = false

    init(path: String) throws {
        self.path = path
        fd = open(path, O_RDONLY)
        guard fd >= 0 else { throw TransferError.openFailure(path, errno) }
        _ = fcntl(fd, F_NOCACHE, 1)
        inBuffer = .allocate(capacity: inCapacity)
        stream = compression_stream(dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!, dst_size: 0,
                                    src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_LZMA) == COMPRESSION_STATUS_OK else {
            close(fd)
            inBuffer.deallocate()
            throw TransferError.compressionFailed("impossibile avviare la decompressione")
        }
    }

    deinit {
        compression_stream_destroy(&stream)
        close(fd)
        inBuffer.deallocate()
    }

    func readFully(_ buffer: inout [UInt8], _ count: Int) throws -> Int {
        var produced = 0
        while produced < count && !finished {
            try refillIfNeeded()
            let before = produced
            let status = buffer.withUnsafeMutableBytes { raw -> compression_status in
                stream.dst_ptr = raw.baseAddress!.assumingMemoryBound(to: UInt8.self) + produced
                stream.dst_size = count - produced
                return compression_stream_process(&stream, inputEOF ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
            }
            produced = count - stream.dst_size

            switch status {
            case COMPRESSION_STATUS_ERROR:
                throw TransferError.compressionFailed("il file \(URL(fileURLWithPath: path).lastPathComponent) non e' un .xz valido o e' danneggiato")
            case COMPRESSION_STATUS_END:
                try startNextStreamOrFinish()
            default:
                if inputEOF && stream.src_size == 0 && produced == before {
                    throw TransferError.compressionFailed("il file .xz e' troncato")
                }
            }
        }
        return produced
    }

    private func refillIfNeeded() throws {
        guard stream.src_size == 0, !inputEOF else { return }
        var n: Int
        repeat { n = read(fd, inBuffer, inCapacity) } while n < 0 && errno == EINTR
        if n < 0 { throw TransferError.readFailed(offset: 0, errno: errno) }
        if n == 0 {
            inputEOF = true
        } else {
            stream.src_ptr = UnsafePointer(inBuffer)
            stream.src_size = n
        }
    }

    /// Dopo la fine di uno stream: se ne segue un altro (file xz concatenati) lo si decodifica, altrimenti e' finita.
    private func startNextStreamOrFinish() throws {
        try refillIfNeeded()
        // Il padding fra stream e' fatto di zeri.
        while stream.src_size > 0, stream.src_ptr.pointee == 0 {
            stream.src_ptr += 1
            stream.src_size -= 1
            if stream.src_size == 0 { try refillIfNeeded() }
        }
        guard stream.src_size > 0 else { finished = true; return }
        let ptr = stream.src_ptr, size = stream.src_size
        compression_stream_destroy(&stream)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_LZMA) == COMPRESSION_STATUS_OK else {
            throw TransferError.compressionFailed("impossibile proseguire la decompressione")
        }
        stream.src_ptr = ptr
        stream.src_size = size
    }
}

// MARK: - Compressione in parallelo

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in bytes { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return ~c
    }

    static func littleEndian(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> UInt32(8 * $0)) & 0xFF) } }
}

/// Unisce piu' stream .xz (uno per blocco di dati) in un solo stream con piu' blocchi: lo stesso formato
/// prodotto da `xz -T0`. Il flusso e' valido ovunque, anche dove i .xz concatenati non sono ammessi.
final class XZStitcher {
    private static let flagsNoCheck: [UInt8] = [0, 0]
    private var records: [(unpadded: UInt64, uncompressed: UInt64)] = []
    private var wroteHeader = false

    private static var header: [UInt8] {
        [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00] + flagsNoCheck + CRC32.littleEndian(CRC32.checksum(flagsNoCheck))
    }

    func add(stream: [UInt8], sink: (UnsafeBufferPointer<UInt8>) throws -> Void) throws {
        guard stream.count >= 24, Array(stream[0..<8]) == Array(XZStitcher.header[0..<8]) else {
            throw TransferError.compressionFailed("blocco .xz non riconosciuto")
        }
        let footerStart = stream.count - 12
        guard stream[footerStart + 10] == 0x59, stream[footerStart + 11] == 0x5A else {
            throw TransferError.compressionFailed("blocco .xz senza piede valido")
        }
        var words: UInt32 = 0
        for i in 0..<4 { words |= UInt32(stream[footerStart + 4 + i]) << UInt32(8 * i) }
        let backward = (Int(words) + 1) * 4
        let indexStart = footerStart - backward
        guard indexStart >= 12 else { throw TransferError.compressionFailed("indice .xz non valido") }

        records += try XZFormat.parseIndex(Array(stream[indexStart..<footerStart]))
        if !wroteHeader {
            try XZStitcher.header.withUnsafeBufferPointer { try sink($0) }
            wroteHeader = true
        }
        try stream.withUnsafeBufferPointer { try sink(UnsafeBufferPointer(rebasing: $0[12..<indexStart])) }
    }

    func finish(sink: (UnsafeBufferPointer<UInt8>) throws -> Void) throws {
        if !wroteHeader {
            try XZStitcher.header.withUnsafeBufferPointer { try sink($0) }
            wroteHeader = true
        }
        var index: [UInt8] = [0x00] + XZStitcher.vli(UInt64(records.count))
        for r in records { index += XZStitcher.vli(r.unpadded) + XZStitcher.vli(r.uncompressed) }
        while index.count % 4 != 0 { index.append(0) }
        index += CRC32.littleEndian(CRC32.checksum(index))

        let backward = CRC32.littleEndian(UInt32(index.count / 4 - 1))
        let footerBody = backward + XZStitcher.flagsNoCheck
        let footer = CRC32.littleEndian(CRC32.checksum(footerBody)) + footerBody + [0x59, 0x5A]
        try (index + footer).withUnsafeBufferPointer { try sink($0) }
    }

    private static func vli(_ value: UInt64) -> [UInt8] {
        var v = value
        var out: [UInt8] = []
        repeat {
            var b = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { b |= 0x80 }
            out.append(b)
        } while v != 0
        return out
    }
}

/// Comprime a blocchi su piu' core e scrive i risultati in ordine. Il compressore di Apple lavora su un solo
/// core (~8 MB/s su dati veri): con i blocchi in parallelo una SD da 16 GB passa da mezz'ora a pochi minuti.
final class ParallelXZEncoder {
    private final class Slot {
        let inputBytes: UInt64
        let done = DispatchSemaphore(value: 0)
        var result: Result<[UInt8], Error> = .failure(TransferError.cancelled)
        init(inputBytes: UInt64) { self.inputBytes = inputBytes }
    }

    private let chunkSize: Int
    private let maxInFlight: Int
    private let sink: (UnsafeBufferPointer<UInt8>) throws -> Void
    private let queue = DispatchQueue(label: "sdclone.xz", qos: .userInitiated, attributes: .concurrent)
    private let stitcher = XZStitcher()
    private var current: [UInt8] = []
    private var inFlight: [Slot] = []

    /// Byte non compressi che sono gia' stati scritti nel file (serve per un avanzamento onesto).
    private(set) var completedInputBytes: UInt64 = 0

    init(chunkSize: Int = 32 << 20, workers: Int? = nil, sink: @escaping (UnsafeBufferPointer<UInt8>) throws -> Void) {
        self.chunkSize = chunkSize
        let n = workers ?? min(max(ProcessInfo.processInfo.activeProcessorCount - 1, 1), 8)
        self.maxInFlight = n + 1
        self.sink = sink
        current.reserveCapacity(chunkSize)
    }

    func append(_ buffer: [UInt8], count: Int) throws {
        var offset = 0
        while offset < count {
            let take = min(chunkSize - current.count, count - offset)
            current.append(contentsOf: buffer[offset..<(offset + take)])
            offset += take
            if current.count >= chunkSize { try submit() }
        }
    }

    func finish() throws {
        if !current.isEmpty { try submit() }
        while !inFlight.isEmpty { try writeOldest() }
        try stitcher.finish(sink: sink)
    }

    private func submit() throws {
        let chunk = current
        current = []
        current.reserveCapacity(chunkSize)
        let slot = Slot(inputBytes: UInt64(chunk.count))
        inFlight.append(slot)
        queue.async {
            slot.result = Result { try XZEncoder().encodeAll(chunk) }
            slot.done.signal()
        }
        while inFlight.count >= maxInFlight { try writeOldest() }
    }

    private func writeOldest() throws {
        let slot = inFlight.removeFirst()
        slot.done.wait()
        try stitcher.add(stream: try slot.result.get(), sink: sink)
        completedInputBytes += slot.inputBytes
    }

    /// Aspetta i blocchi in volo (da chiamare se si abbandona la compressione, prima di liberare le risorse).
    func abandon() {
        for slot in inFlight { slot.done.wait() }
        inFlight.removeAll()
    }
}

// MARK: - Formato

public enum XZFormat {
    private static let magic: [UInt8] = [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]

    /// Riconosce un `.xz` dai primi byte (non dall'estensione).
    public static func isXZ(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        return Array((try? h.read(upToCount: 6)) ?? Data()) == magic
    }

    /// Legge i record (dimensione "unpadded" e non compressa di ogni blocco) da un indice .xz.
    static func parseIndex(_ index: [UInt8]) throws -> [(unpadded: UInt64, uncompressed: UInt64)] {
        guard index.first == 0 else { throw TransferError.compressionFailed("indice .xz non valido") }
        var pos = 1
        func varint() throws -> UInt64 {
            var value: UInt64 = 0, shift: UInt64 = 0
            while pos < index.count, shift < 63 {
                let b = index[pos]; pos += 1
                value |= UInt64(b & 0x7F) << shift
                if b & 0x80 == 0 { return value }
                shift += 7
            }
            throw TransferError.compressionFailed("indice .xz non valido")
        }
        let count = try varint()
        var records: [(UInt64, UInt64)] = []
        for _ in 0..<count { records.append((try varint(), try varint())) }
        return records
    }

    /// Come `isXZ`, ma se il file non si puo' leggere lo dice invece di rispondere "non e' xz": un permesso negato da
    /// macOS non deve diventare "immagine non valida".
    static func checkXZ(_ path: String) throws -> Bool {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { throw TransferError.openFailure(path, errno) }
        defer { close(fd) }
        var head = [UInt8](repeating: 0, count: 6)
        let n = pread(fd, &head, 6, 0)
        guard n >= 0 else { throw TransferError.readFailed(offset: 0, errno: errno) }
        return n == 6 && head == magic
    }

    /// Dimensione dei dati una volta decompressi, letta dall'indice in fondo al file (senza decomprimere).
    public static func uncompressedSize(of url: URL) throws -> UInt64 {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw TransferError.openFailure(url.path, errno) }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw TransferError.cannotOpenSource(url.path, errno) }

        func bytes(_ count: Int, at offset: Int64) throws -> [UInt8] {
            guard offset >= 0 else { throw TransferError.compressionFailed("file .xz troncato") }
            var buf = [UInt8](repeating: 0, count: count)
            let n = pread(fd, &buf, count, off_t(offset))
            guard n == count else { throw TransferError.compressionFailed("file .xz troncato") }
            return buf
        }

        var end = Int64(st.st_size)
        var total: UInt64 = 0
        while end > 0 {
            // padding di zeri fra gli stream (multipli di 4 byte)
            while end >= 4, try bytes(4, at: end - 4) == [0, 0, 0, 0] { end -= 4 }
            if end == 0 { break }
            let footer = try bytes(12, at: end - 12)
            guard footer[10] == 0x59, footer[11] == 0x5A else {
                throw TransferError.compressionFailed("non e' un file .xz valido")
            }
            var backwardWords: UInt32 = 0
            for i in 0..<4 { backwardWords |= UInt32(footer[4 + i]) << UInt32(8 * i) }
            let backward = (Int64(backwardWords) + 1) * 4
            let index = try bytes(Int(backward), at: end - 12 - backward)
            var blocksBytes: UInt64 = 0
            for r in try parseIndex(index) {
                total += r.uncompressed
                blocksBytes += (r.unpadded + 3) & ~UInt64(3)
            }
            end -= Int64(12 + blocksBytes) + backward + 12
        }
        return total
    }
}
