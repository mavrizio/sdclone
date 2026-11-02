import Foundation
import CryptoKit

public struct BackupResult: Equatable, Sendable {
    /// Byte letti dalla sorgente (e quindi SHA256 e avanzamento si riferiscono a questi).
    public let bytesCopied: UInt64
    /// SHA256 dei dati *non compressi*, anche se il file scritto e' un .xz.
    public let sha256: String
    /// Dimensione del file scritto (uguale a `bytesCopied` senza compressione).
    public let outputBytes: UInt64
}

/// Copia i primi `length` byte di `source` (dispositivo raw o file) in `destination`,
/// calcolando lo SHA256 durante la copia. Non conosce i dischi: la scelta del dispositivo e
/// la verifica di sicurezza spettano al chiamante. Legge soltanto dalla sorgente.
public struct BackupEngine {
    public var blockSize: Int
    /// Dimensione dei blocchi compressi in parallelo (default 32 MiB; i test la riducono).
    public var xzChunkSize: Int

    public init(blockSize: Int = 4 * 1024 * 1024, xzChunkSize: Int = 32 << 20) {
        precondition(blockSize > 0 && blockSize % PartitionLayout.sectorSize == 0)
        self.blockSize = blockSize
        self.xzChunkSize = xzChunkSize
    }

    /// Legge l'intestazione di un dispositivo/file per decidere quanto copiare.
    public func layout(of source: String, diskSize: UInt64) throws -> PartitionLayout.Result {
        let fd = open(source, O_RDONLY)
        guard fd >= 0 else { throw TransferError.openFailure(source, errno) }
        defer { close(fd) }
        var header = [UInt8](repeating: 0, count: 4096)   // multiplo di 512: richiesto dal nodo raw
        let n = pread(fd, &header, header.count, 0)
        return PartitionLayout.analyze(header: n > 0 ? Data(header[0..<n]) : Data(), diskSize: diskSize)
    }

    /// Con `compress` il file scritto e' un `.xz`; la sorgente puo' essere anche un normale file `.img`.
    public func run(source: String, length: UInt64, destination: URL, compress: Bool = false,
                    progress: (TransferProgress) -> Void = { _ in },
                    isCancelled: () -> Bool = { false }) throws -> BackupResult {
        // Con la compressione la dimensione finale non e' nota: se lo spazio finisce lo si scopre in scrittura.
        if !compress { try checkSpace(length: length, destination: destination) }

        let src = open(source, O_RDONLY)
        guard src >= 0 else { throw TransferError.openFailure(source, errno) }
        defer { close(src) }
        _ = fcntl(src, F_NOCACHE, 1)   // niente cache di sistema per un dump sequenziale

        let dst = open(destination.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard dst >= 0 else { throw TransferError.cannotCreateDestination(destination.path, errno) }
        var finished = false
        defer {
            close(dst)
            // Un file parziale sembrerebbe un backup valido: lo si toglie se non e' finito.
            if !finished { unlink(destination.path) }
        }

        var hasher = SHA256()
        var tracker = ProgressTracker(total: length)
        var buffer = [UInt8](repeating: 0, count: blockSize)
        var done: UInt64 = 0
        var written: UInt64 = 0
        let clock = Stopwatch()
        let encoder = compress ? ParallelXZEncoder(chunkSize: xzChunkSize) { bytes in
            try BlockIO.writeFully(dst, bytes)
            written += UInt64(bytes.count)
        } : nil
        defer { encoder?.abandon() }

        progress(tracker.update(bytesDone: 0, now: clock.seconds()))
        while done < length {
            if isCancelled() { throw TransferError.cancelled }
            let want = Int(min(UInt64(blockSize), length - done))
            let got = try BlockIO.readFully(src, &buffer, want, offset: done)
            guard got == want else { throw TransferError.shortRead(expected: length, got: done + UInt64(got)) }
            if let encoder {
                try encoder.append(buffer, count: got)
            } else {
                try BlockIO.writeFully(dst, buffer, count: got)
                written += UInt64(got)
            }
            BlockIO.update(&hasher, buffer, count: got)
            done += UInt64(got)
            // Con la compressione si conta cio' che e' gia' stato scritto, non cio' che e' stato solo letto.
            progress(tracker.update(bytesDone: encoder?.completedInputBytes ?? done, now: clock.seconds()))
        }
        try encoder?.finish()
        progress(tracker.update(bytesDone: done, now: clock.seconds()))
        guard fsync(dst) == 0 else { throw TransferError.writeFailed(errno: errno) }
        finished = true
        return BackupResult(bytesCopied: done, sha256: BlockIO.hex(hasher), outputBytes: written)
    }

    private func checkSpace(length: UInt64, destination: URL) throws {
        let dir = destination.deletingLastPathComponent()
        let values = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let avail = values?.volumeAvailableCapacityForImportantUsage, UInt64(avail) < length {
            throw TransferError.insufficientSpace(needed: length, available: UInt64(avail))
        }
    }
}
