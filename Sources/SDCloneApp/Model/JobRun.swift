import Foundation
import Observation
import SDCore

/// Un backup o un ripristino, dall'avvio all'esito.
@MainActor @Observable
final class JobRun {
    enum Kind { case backup, restore, compress, optimize }

    enum Outcome: Equatable {
        case success
        case failed(String)
        case cancelled
    }

    let kind: Kind
    /// Nil per la compressione di un backup gia' fatto, che non coinvolge nessuna scheda.
    let disk: DiskInfo?
    /// File di destinazione (backup, compressione, ottimizzazione) o immagine di origine (ripristino).
    var file: URL
    /// Byte che si prevede di trattare (serve alla demo).
    let expectedBytes: UInt64
    /// Backup che scrive un .img.xz.
    let compressed: Bool
    let startedAt = Date()

    var status = JobStatus(state: .starting, phase: .preparing)
    var speedHistory: [Double] = []
    var finishedAt: Date?
    var outcome: Outcome?
    /// Finche' l'utente non ha inserito la password non c'e' ancora nessuno stato dall'helper.
    var waitingForAuthorization = true
    var cancelRequested = false

    /// Solo per l'ottimizzazione: cosa si fa, a che punto e com'e' andata.
    var optimizeOptions = ImageOptimizer.Options()
    var optimizeStep: ImageOptimizer.Step?
    var optimizeResult: ImageOptimizer.Result?

    init(kind: Kind, disk: DiskInfo?, file: URL, expectedBytes: UInt64 = 0, compressed: Bool = false) {
        self.kind = kind
        self.disk = disk
        self.file = file
        self.expectedBytes = expectedBytes
        self.compressed = compressed
    }

    var accent: Accent {
        switch kind {
        case .backup: return .backup
        case .restore: return .restore
        case .compress: return .library
        case .optimize: return .optimize
        }
    }

    var isFinished: Bool { outcome != nil }

    var elapsed: TimeInterval { (finishedAt ?? Date()).timeIntervalSince(startedAt) }

    var title: String {
        let noun: String
        switch kind {
        case .backup: noun = "Backup"
        case .restore: noun = "Ripristino"
        case .compress: noun = "Compressione"
        case .optimize: noun = "Ottimizzazione"
        }
        let feminine = kind == .compress || kind == .optimize
        switch outcome {
        case nil: return "\(noun) in corso"
        case .success?: return feminine ? "\(noun) completata" : "\(noun) completato"
        case .failed?: return feminine ? "\(noun) non riuscita" : "\(noun) non riuscito"
        case .cancelled?: return "Operazione annullata"
        }
    }

    var phaseLabel: String {
        if waitingForAuthorization { return "In attesa dell'autorizzazione…" }
        if kind == .optimize {
            switch optimizeStep {
            case nil: return "Preparazione…"
            case .extracting?: return "Estraggo la partizione Linux dall'immagine…"
            case .checking?: return "Controllo il filesystem (e2fsck)…"
            case .cleaning?: return "Tolgo le cronologie…"
            case .shrinking?: return "Riduco il filesystem al minimo (resize2fs)…"
            case .assembling?: return "Ricompongo l'immagine…"
            case .verifying?: return "Verifico il risultato…"
            case .compressing?: return "Comprimo in .xz…"
            }
        }
        switch status.phase {
        case .preparing: return kind == .compress ? "Preparazione…" : "Preparazione della scheda…"
        case .copying:
            switch kind {
            case .backup: return compressed ? "Copia e compressione dei dati…" : "Copia dei dati…"
            case .restore: return "Scrittura sulla scheda…"
            case .compress, .optimize: return "Compressione dei dati…"
            }
        case .verifying: return "Verifica di ciò che è stato scritto…"
        case .finishing: return "Ultimi controlli…"
        }
    }

    /// Le tappe mostrate in alto, con quella attiva.
    var steps: [String] {
        switch kind {
        case .backup: return ["Preparazione", compressed ? "Copia e compressione" : "Copia", "Completato"]
        case .restore: return ["Preparazione", "Scrittura", "Verifica", "Completato"]
        case .compress: return ["Preparazione", "Compressione", "Completato"]
        case .optimize: return optimizeSteps.map(\.title) + ["Completato"]
        }
    }

    /// Tappe dell'ottimizzazione: ognuna raggruppa uno o piu' passi del motore.
    private var optimizeSteps: [(title: String, covers: [ImageOptimizer.Step])] {
        let o = optimizeOptions
        var list: [(String, [ImageOptimizer.Step])] = []
        if o.rebuilds { list.append(("Estrazione", [.extracting, .checking])) }
        if o.clean { list.append(("Pulizia", [.cleaning])) }
        if o.shrink { list.append(("Riduzione", [.shrinking])) }
        if o.rebuilds { list.append(("Verifica", [.assembling, .verifying])) }
        if o.compress { list.append(("Compressione", [.compressing])) }
        return list
    }

    var activeStep: Int {
        if outcome == .success { return steps.count - 1 }
        if waitingForAuthorization { return 0 }
        if kind == .optimize {
            guard let step = optimizeStep else { return 0 }
            return optimizeSteps.firstIndex { $0.covers.contains(step) } ?? 0
        }
        switch status.phase {
        case .preparing: return 0
        case .copying: return 1
        case .verifying: return kind == .restore ? 2 : 1
        case .finishing: return steps.count - 1
        }
    }

    func apply(_ s: JobStatus) {
        waitingForAuthorization = false
        status = s
        if s.state == .running, s.bytesPerSecond > 0 {
            speedHistory.append(s.bytesPerSecond)
            if speedHistory.count > 90 { speedHistory.removeFirst(speedHistory.count - 90) }
        }
    }

    /// Avanzamento dell'ottimizzazione: un passo nuovo riparte da zero (anche il grafico della velocita').
    func applyOptimize(_ p: ImageOptimizer.Progress) {
        if p.step != optimizeStep {
            optimizeStep = p.step
            speedHistory.removeAll()
        }
        var s = JobStatus(state: .running, phase: p.step == .verifying ? .verifying : .copying)
        if let t = p.transfer { s = s.updating(t, phase: s.phase) }
        apply(s)
    }

    func conclude(_ outcome: Outcome) {
        guard self.outcome == nil else { return }
        finishedAt = Date()
        self.outcome = outcome
        if outcome == .success {
            status.bytesDone = status.bytesTotal
            status.secondsRemaining = 0
        }
    }
}
