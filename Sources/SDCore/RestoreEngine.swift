import Foundation
import CryptoKit

public enum RestorePhase: Sendable {
    case writing
    case verifying
}

public struct RestoreProgress: Equatable, Sendable {
    public let phase: RestorePhase
    public let transfer: TransferProgress
}

public struct RestoreResult: Equatable, Sendable {
    public let bytesWritten: UInt64
    /// SHA256 dell'immagine; e' anche quello riletto dalla SD, altrimenti si lancia `verificationFailed`.
    public let sha256: String
}

/// Scrive un'immagine su `target` (nodo raw o file) e la rilegge per verificarla.
/// Come `BackupEngine` non decide *dove* scrivere: il chiamante deve aver passato la destinazione
/// da `SafetyPolicy` e smontato il disco prima di chiamare `run`.
public struct RestoreEngine {
    public var blockSize: Int

    public init(blockSize: Int = 4 * 1024 * 1024) {
        precondition(blockSize > 0 && blockSize % PartitionLayout.sectorSize == 0)
        self.blockSize = blockSize
    }

    /// Dimensione dell'immagine (decompressa, se e' un .xz), se valida per una scrittura su dispositivo a settori.
    public func imageSize(_ image: URL) throws -> UInt64 {
        let size = try XZFormat.checkXZ(image.path) ? try XZFormat.uncompressedSize(of: image) : try BlockIO.fileSize(image.path)
        guard size > 0, size % UInt64(PartitionLayout.sectorSize) == 0 else {
            throw TransferError.imageEmptyOrNotSectorAligned(size)
        }
        return size
    }

    public func run(image: URL, target: String, targetCapacity: UInt64,
                    progress: (RestoreProgress) -> Void = { _ in },
                    isCancelled: () -> Bool = { false }) throws -> RestoreResult {
        let length = try imageSize(image)
        guard length <= targetCapacity else {
            throw TransferError.imageTooLarge(image: length, capacity: targetCapacity)
        }

        let reader: SequentialReader = try XZFormat.checkXZ(image.path) ? try XZFileReader(path: image.path)
                                                           : try RawFileReader(path: image.path)

        // Nessun O_CREAT/O_TRUNC: si scrive solo su un dispositivo (o file) che esiste gia'.
        // Lo stesso descrittore serve per scrittura e verifica: alla chiusura macOS rilegge le partizioni e prova a
        // montarle, e non deve succedere prima che la verifica sia finita.
        let dst = open(target, O_RDWR)
        guard dst >= 0 else { throw TransferError.openFailure(target, errno, writing: true) }
        defer { close(dst) }
        _ = fcntl(dst, F_NOCACHE, 1)

        var hasher = SHA256()
        var tracker = ProgressTracker(total: length)
        var buffer = [UInt8](repeating: 0, count: blockSize)
        var done: UInt64 = 0
        let clock = Stopwatch()

        progress(RestoreProgress(phase: .writing, transfer: tracker.update(bytesDone: 0, now: clock.seconds())))
        while done < length {
            if isCancelled() { throw TransferError.cancelled }
            let want = Int(min(UInt64(blockSize), length - done))
            let got = try reader.readFully(&buffer, want)
            guard got == want else { throw TransferError.shortRead(expected: length, got: done + UInt64(got)) }
            try BlockIO.writeFully(dst, buffer, count: got)
            BlockIO.update(&hasher, buffer, count: got)
            done += UInt64(got)
            progress(RestoreProgress(phase: .writing, transfer: tracker.update(bytesDone: done, now: clock.seconds())))
        }
        _ = fsync(dst)   // sul nodo raw puo' non essere supportato: la verifica che segue e' il vero controllo

        let expected = BlockIO.hex(hasher)
        let actual = try BlockIO.sha256(fd: dst, length: length, blockSize: blockSize,
                                        progress: { progress(RestoreProgress(phase: .verifying, transfer: $0)) },
                                        isCancelled: isCancelled)
        guard actual == expected else { throw TransferError.verificationFailed(expected: expected, actual: actual) }
        return RestoreResult(bytesWritten: length, sha256: expected)
    }
}
