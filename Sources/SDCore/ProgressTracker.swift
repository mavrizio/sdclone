import Foundation

public struct TransferProgress: Equatable, Sendable {
    public let bytesDone: UInt64
    public let bytesTotal: UInt64
    /// Byte al secondo, media mobile sugli ultimi secondi.
    public let bytesPerSecond: Double
    /// Secondi rimanenti; nil finche' non c'e' una stima affidabile.
    public let secondsRemaining: Double?

    public init(bytesDone: UInt64, bytesTotal: UInt64, bytesPerSecond: Double, secondsRemaining: Double?) {
        self.bytesDone = bytesDone
        self.bytesTotal = bytesTotal
        self.bytesPerSecond = bytesPerSecond
        self.secondsRemaining = secondsRemaining
    }

    public var fraction: Double { bytesTotal == 0 ? 1 : min(1, Double(bytesDone) / Double(bytesTotal)) }
}

/// Velocita' e tempo stimato.
///
/// La velocita' mostrata e' la media degli ultimi secondi (puo' variare molto, soprattutto comprimendo). Il tempo
/// rimanente invece e' filtrato per non seguirla a scatti: usa una velocita' mediata su un tempo piu' lungo, scende da
/// solo di un secondo al secondo e si avvicina alla nuova stima lentamente, in scala logaritmica (una stima che triplica
/// fa scivolare il numero in un paio di minuti invece di farlo saltare).
public struct ProgressTracker {
    private let total: UInt64
    private let window: TimeInterval
    private let speedTau: TimeInterval
    private let etaTau: TimeInterval
    private var samples: [(time: TimeInterval, bytes: UInt64)] = []

    // stato del filtro sul tempo rimanente
    private var startTime: TimeInterval?
    private var startBytes: UInt64 = 0
    private var lastTime: TimeInterval = 0
    private var lastBytes: UInt64 = 0
    private var smoothSpeed: Double?
    private var shownETA: Double?
    private var lastShownTime: TimeInterval = 0

    /// - Parameters:
    ///   - window: finestra (s) della velocita' mostrata.
    ///   - speedTau: costante di tempo (s) della velocita' usata per stimare il tempo rimanente.
    ///   - etaTau: costante di tempo (s) con cui il tempo mostrato raggiunge la stima.
    public init(total: UInt64, window: TimeInterval = 5, speedTau: TimeInterval = 30, etaTau: TimeInterval = 40) {
        self.total = total
        self.window = window
        self.speedTau = speedTau
        self.etaTau = etaTau
    }

    /// `now` in secondi (monotono). Passato dall'esterno per poter testare.
    public mutating func update(bytesDone: UInt64, now: TimeInterval) -> TransferProgress {
        samples.append((now, bytesDone))
        while samples.count > 2, now - samples[1].time >= window { samples.removeFirst() }

        var speed = 0.0
        if let first = samples.first, now > first.time, bytesDone >= first.bytes {
            speed = Double(bytesDone - first.bytes) / (now - first.time)
        }
        return TransferProgress(bytesDone: bytesDone, bytesTotal: total, bytesPerSecond: speed,
                                secondsRemaining: filteredETA(bytesDone: bytesDone, now: now))
    }

    private mutating func filteredETA(bytesDone: UInt64, now: TimeInterval) -> Double? {
        if bytesDone >= total {
            shownETA = 0
            return 0
        }
        guard let start = startTime else {
            startTime = now
            startBytes = bytesDone
            lastTime = now
            lastBytes = bytesDone
            return nil
        }
        let elapsed = now - start

        // velocita' mediata nel tempo (esponenziale, pesata sul tempo trascorso fra un campione e l'altro)
        let dt = now - lastTime
        if let s = smoothSpeed {
            if dt > 0, bytesDone >= lastBytes {
                let instant = Double(bytesDone - lastBytes) / dt
                smoothSpeed = s + (instant - s) * (1 - exp(-dt / speedTau))
                lastTime = now
                lastBytes = bytesDone
            }
        } else if elapsed > 0, bytesDone >= startBytes {
            smoothSpeed = Double(bytesDone - startBytes) / elapsed   // all'inizio: media dall'avvio
            lastTime = now
            lastBytes = bytesDone
        }

        guard elapsed >= 1, let speedEstimate = smoothSpeed, speedEstimate > 0 else { return nil }
        let target = Double(total - bytesDone) / speedEstimate

        guard let shown = shownETA else {
            shownETA = target
            lastShownTime = now
            return target
        }
        let step = max(now - lastShownTime, 0)
        let base = max(shown - step, 1)            // scende da solo di 1 s al secondo
        let goal = max(target, 1)
        let next = exp(log(base) + (log(goal) - log(base)) * (1 - exp(-step / etaTau)))
        shownETA = next
        lastShownTime = now
        return next
    }
}

public enum DurationFormat {
    public static func string(_ seconds: Double?) -> String {
        guard let s = seconds, s.isFinite else { return "--:--" }
        let t = Int(s.rounded())
        return t >= 3600
            ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
            : String(format: "%02d:%02d", t / 60, t % 60)
    }
}
