import Foundation
import CryptoKit

/// Lettura/scrittura a blocchi condivise da backup e ripristino.
enum BlockIO {
    static func readFully(_ fd: Int32, _ buf: inout [UInt8], _ count: Int, offset: UInt64) throws -> Int {
        var total = 0
        while total < count {
            let n = buf.withUnsafeMutableBytes {
                pread(fd, $0.baseAddress! + total, count - total, off_t(offset) + off_t(total))
            }
            if n < 0 {
                if errno == EINTR { continue }
                throw TransferError.readFailed(offset: offset + UInt64(total), errno: errno)
            }
            if n == 0 { break }
            total += n
        }
        return total
    }

    static func writeFully(_ fd: Int32, _ buf: [UInt8], count: Int) throws {
        var written = 0
        while written < count {
            let n = buf.withUnsafeBytes { write(fd, $0.baseAddress! + written, count - written) }
            if n < 0 {
                if errno == EINTR { continue }
                throw TransferError.writeFailed(errno: errno)
            }
            written += n
        }
    }

    static func writeFully(_ fd: Int32, _ bytes: UnsafeBufferPointer<UInt8>) throws {
        var written = 0
        while written < bytes.count {
            let n = write(fd, bytes.baseAddress! + written, bytes.count - written)
            if n < 0 {
                if errno == EINTR { continue }
                throw TransferError.writeFailed(errno: errno)
            }
            written += n
        }
    }

    static func update(_ hasher: inout SHA256, _ buf: [UInt8], count: Int) {
        buf.withUnsafeBytes { hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[0..<count])) }
    }

    static func hex(_ hasher: SHA256) -> String {
        hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// SHA256 dei primi `length` byte di un file/dispositivo aperto in lettura.
    static func sha256(fd: Int32, length: UInt64, blockSize: Int,
                       progress: (TransferProgress) -> Void,
                       isCancelled: () -> Bool) throws -> String {
        var hasher = SHA256()
        var tracker = ProgressTracker(total: length)
        var buffer = [UInt8](repeating: 0, count: blockSize)
        var done: UInt64 = 0
        let clock = Stopwatch()
        progress(tracker.update(bytesDone: 0, now: clock.seconds()))
        while done < length {
            if isCancelled() { throw TransferError.cancelled }
            let want = Int(min(UInt64(blockSize), length - done))
            let got = try readFully(fd, &buffer, want, offset: done)
            guard got == want else { throw TransferError.shortRead(expected: length, got: done + UInt64(got)) }
            update(&hasher, buffer, count: got)
            done += UInt64(got)
            progress(tracker.update(bytesDone: done, now: clock.seconds()))
        }
        return hex(hasher)
    }

    static func fileSize(_ path: String) throws -> UInt64 {
        var st = stat()
        guard stat(path, &st) == 0 else { throw TransferError.openFailure(path, errno) }
        return UInt64(st.st_size)
    }
}

struct Stopwatch {
    private let start = DispatchTime.now().uptimeNanoseconds
    func seconds() -> TimeInterval { Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9 }
}
