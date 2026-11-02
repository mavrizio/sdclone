import Foundation

/// Stato di un backup/ripristino in corso. Lo scrive il comando `sdclone` (che gira come root)
/// in un file JSON e lo legge l'app, che non ha i privilegi per parlarci direttamente.
public struct JobStatus: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case starting, running, done, failed, cancelled
    }

    public enum Phase: String, Codable, Sendable {
        case preparing, copying, verifying, finishing
    }

    public var state: State
    public var phase: Phase
    public var bytesDone: UInt64
    public var bytesTotal: UInt64
    public var bytesPerSecond: Double
    public var secondsRemaining: Double?
    /// Valorizzati a lavoro finito.
    public var sha256: String?
    public var outputPath: String?
    /// Dimensione del file scritto (con la compressione e' minore di `bytesTotal`).
    public var outputBytes: UInt64?
    /// Motivo, se `state == .failed`.
    public var message: String?
    /// Vero se il lavoro e' fallito perche' macOS nega l'accesso diretto al disco (serve "Accesso completo al disco").
    public var needsFullDiskAccess: Bool?

    public init(state: State, phase: Phase, bytesDone: UInt64 = 0, bytesTotal: UInt64 = 0,
                bytesPerSecond: Double = 0, secondsRemaining: Double? = nil,
                sha256: String? = nil, outputPath: String? = nil, message: String? = nil) {
        self.state = state
        self.phase = phase
        self.bytesDone = bytesDone
        self.bytesTotal = bytesTotal
        self.bytesPerSecond = bytesPerSecond
        self.secondsRemaining = secondsRemaining
        self.sha256 = sha256
        self.outputPath = outputPath
        self.message = message
    }

    public var fraction: Double { bytesTotal == 0 ? 0 : min(1, Double(bytesDone) / Double(bytesTotal)) }

    public var isFinished: Bool { state == .done || state == .failed || state == .cancelled }

    public func updating(_ p: TransferProgress, phase: Phase) -> JobStatus {
        var s = self
        s.state = .running
        s.phase = phase
        s.bytesDone = p.bytesDone
        s.bytesTotal = p.bytesTotal
        s.bytesPerSecond = p.bytesPerSecond
        s.secondsRemaining = p.secondsRemaining
        return s
    }

    // MARK: - File

    /// Scrittura atomica: chi legge vede sempre un JSON completo.
    public func write(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    public static func read(from url: URL) -> JobStatus? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(JobStatus.self, from: data)
    }
}
