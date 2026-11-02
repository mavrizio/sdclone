import XCTest
@testable import SDCore

final class ProgressTrackerTests: XCTestCase {
    func testSteadySpeedGivesSpeedAndRemainingTime() {
        var t = ProgressTracker(total: 1000)
        _ = t.update(bytesDone: 0, now: 0)
        let p = t.update(bytesDone: 200, now: 2)   // 100 B/s, ne restano 800
        XCTAssertEqual(p.bytesPerSecond, 100, accuracy: 0.001)
        XCTAssertEqual(p.secondsRemaining ?? -1, 8, accuracy: 0.001)
        XCTAssertEqual(p.fraction, 0.2, accuracy: 0.0001)
    }

    func testNoEstimateInTheFirstSecond() {
        var t = ProgressTracker(total: 1000)
        _ = t.update(bytesDone: 0, now: 0)
        XCTAssertNil(t.update(bytesDone: 50, now: 0.4).secondsRemaining)
    }

    func testSpeedUsesOnlyTheRecentWindow() {
        var t = ProgressTracker(total: 100_000, window: 5)
        _ = t.update(bytesDone: 0, now: 0)
        _ = t.update(bytesDone: 10_000, now: 1)      // fase veloce: 10 kB/s
        for s in 2...20 { _ = t.update(bytesDone: 10_000 + UInt64(s - 1) * 100, now: Double(s)) }   // poi 100 B/s
        let p = t.update(bytesDone: 10_000 + 20 * 100, now: 21)
        XCTAssertEqual(p.bytesPerSecond, 100, accuracy: 5)
    }

    func testFinishedMeansZeroRemaining() {
        var t = ProgressTracker(total: 500)
        _ = t.update(bytesDone: 0, now: 0)
        let p = t.update(bytesDone: 500, now: 3)
        XCTAssertEqual(p.secondsRemaining, 0)
        XCTAssertEqual(p.fraction, 1)
    }

    func testEmptyTransferIsComplete() {
        var t = ProgressTracker(total: 0)
        XCTAssertEqual(t.update(bytesDone: 0, now: 0).fraction, 1)
    }

    // MARK: - Tempo rimanente filtrato

    /// Trasferimento da 16 GB con velocita' che cambia di 10 volte ogni 25 s e blocchi che arrivano a scatti,
    /// come la compressione. Restituisce (tempo del filtro, tempo "ingenuo" rimanenti/velocita' degli ultimi 5 s).
    private func simulateBurstyTransfer() -> (filtered: [Double], naive: [Double]) {
        let total: UInt64 = 16_000_000_000
        var t = ProgressTracker(total: total)
        var done: UInt64 = 0
        var filtered: [Double] = [], naive: [Double] = []
        var recent: [(Double, UInt64)] = [(0, 0)]
        var now = 0.0
        _ = t.update(bytesDone: 0, now: 0)
        while done < total && now < 20_000 {
            now += 1
            let fast = Int(now / 25) % 2 == 0
            let rate: Double = fast ? 40e6 : 4e6
            // i byte "completati" arrivano a blocchi da 32 MiB
            let block = UInt64(32 << 20)
            let produced = UInt64(rate) + UInt64(Double(done % block))
            done = min(total, done + (produced / block) * block + (Int(now) % 7 == 0 ? block : 0))
            let p = t.update(bytesDone: done, now: now)
            recent.append((now, done)); recent.removeAll { now - $0.0 > 5 }
            if let eta = p.secondsRemaining, eta > 0, now > 20 { filtered.append(eta) }
            if let first = recent.first, now > first.0, done > first.1 {
                naive.append(Double(total - done) / (Double(done - first.1) / (now - first.0)))
            }
        }
        return (filtered, naive)
    }

    /// Variazione massima da un secondo al successivo, al netto del conto alla rovescia naturale (-1 s), contando solo
    /// i momenti in cui mancano almeno 2 minuti: negli ultimi secondi 1 s di scarto pesa molto in percentuale ma non si nota.
    private func maxRelativeStep(_ v: [Double]) -> Double {
        zip(v, v.dropFirst()).filter { $0.0 >= 120 }.map { abs($1 - ($0 - 1)) / $0 }.max() ?? 0
    }

    func testFilteredETAIsMuchSmootherThanInstantSpeedEstimate() {
        let (filtered, naive) = simulateBurstyTransfer()
        let f = maxRelativeStep(filtered), n = maxRelativeStep(naive)
        print("salto massimo del tempo stimato in 1 s: filtrato \(String(format: "%.1f", f * 100))%  ingenuo \(String(format: "%.0f", n * 100))%")
        XCTAssertGreaterThan(n, 0.3, "lo scenario deve essere davvero a scatti")
        XCTAssertLessThan(f, 0.03, "il tempo filtrato non deve cambiare di piu' del 3% in un secondo")
        XCTAssertLessThan(f * 8, n)
    }

    func testFilteredETACountsDownOneSecondPerSecondWhenSpeedIsSteady() {
        var t = ProgressTracker(total: 100_000_000_000)
        _ = t.update(bytesDone: 0, now: 0)
        var etas: [Double] = []
        for s in 1...120 { etas.append(t.update(bytesDone: UInt64(s) * 10_000_000, now: Double(s)).secondsRemaining ?? .nan) }
        // velocita' costante 10 MB/s -> tempo vero = 10000 - s
        XCTAssertEqual(etas[9], 10_000 - 10, accuracy: 10_000 * 0.005)
        XCTAssertEqual(etas[119], 10_000 - 120, accuracy: 10_000 * 0.005)
        XCTAssertEqual(etas[100] - etas[110], 10, accuracy: 0.5, "scende di un secondo al secondo")
    }

    func testFilteredETAConvergesToNewRealityAfterASustainedSpeedChange() {
        var t = ProgressTracker(total: 100_000_000_000)
        var now = 0.0, done: UInt64 = 0
        _ = t.update(bytesDone: 0, now: 0)
        var last: Double?
        for step in 0..<1500 {             // 10 MB/s per 5 min, poi 2,5 MB/s
            now += 1
            done += step < 300 ? 10_000_000 : 2_500_000
            last = t.update(bytesDone: done, now: now).secondsRemaining
        }
        let truth = Double(100_000_000_000 - done) / 2_500_000
        XCTAssertEqual(last ?? 0, truth, accuracy: truth * 0.10, "dopo un cambio duraturo deve raggiungere la stima reale")
    }

    func testDurationFormat() {
        XCTAssertEqual(DurationFormat.string(nil), "--:--")
        XCTAssertEqual(DurationFormat.string(75), "01:15")
        XCTAssertEqual(DurationFormat.string(3725), "1:02:05")
        XCTAssertEqual(DurationFormat.string(.infinity), "--:--")
    }
}
