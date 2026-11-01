import Foundation

public enum ByteFormat {
    /// Formato decimale come Finder/diskutil ("64,0 GB").
    public static func string(_ bytes: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(clamping: bytes))
    }
}
