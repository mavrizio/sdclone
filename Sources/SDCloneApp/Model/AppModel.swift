import Foundation
import AppKit
import Observation
import UserNotifications
import SDCore

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    var mode: Mode = .backup
    private(set) var disks: [DiskInfo] = []
    var selectedDiskID: String?

    /// Salva i backup come .img.xz (ricordato fra un avvio e l'altro; di default si'.)
    var compressBackups: Bool = UserDefaults.standard.object(forKey: "compressBackups") as? Bool ?? true {
        didSet { UserDefaults.standard.set(compressBackups, forKey: "compressBackups") }
    }

    /// Cartella dei backup e dell'Archivio: l'ultima scelta viene ricordata.
    var backupFolder: URL = AppModel.savedBackupFolder() {
        didSet { if !demo { UserDefaults.standard.set(backupFolder.path, forKey: "backupFolder") } }
    }
    var backupName = ""
    var nameEdited = false

    var restoreImage: URL?
    private(set) var library: [BackupEntry] = []

    /// Ottimizza: immagine scelta, sua analisi e operazioni da fare (ricordate fra un avvio e l'altro).
    var optimizeImage: URL? { didSet { if optimizeImage != oldValue { analyzeOptimizeImage() } } }
    private(set) var optimizeAnalysis: ImageAnalysis?
    private(set) var optimizeAnalysisError: String?
    private(set) var analyzingImage = false
    private(set) var e2fsTools: E2fsTools?
    var optimizeOptions: ImageOptimizer.Options = AppModel.loadOptimizeOptions() {
        didSet { AppModel.saveOptimizeOptions(optimizeOptions) }
    }

    var job: JobRun?
    var showRestoreConfirm = false

    /// Schede in corso di espulsione e ultimo errore da mostrare.
    private(set) var ejecting: Set<String> = []
    var ejectError: String?

    /// `SDCLONE_DEMO=1`: dischi e avanzamento simulati, nessuna password.
    let demo = ProcessInfo.processInfo.environment["SDCLONE_DEMO"] == "1"

    @ObservationIgnored private var demoStateApplied = false
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var jobTask: Task<Void, Never>?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var runDirectory: URL?
    @ObservationIgnored private var cancelFile: URL?

    init() {
        if demo { disks = DemoData.disks }
        refreshLibrary()
        refreshTools()
    }

    // MARK: - Dischi

    var selectedDisk: DiskInfo? { disks.first { $0.identifier == selectedDiskID } }

    func select(_ disk: DiskInfo) {
        selectedDiskID = disk.identifier
        if !nameEdited { backupName = suggestedName(for: disk) }
    }

    func startMonitoring() {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshDisks()
                try? await Task.sleep(for: .seconds(2.5))
            }
        }
    }

    func refreshDisks() async {
        if demo || hasRunningJob { return }
        let found = await Task.detached(priority: .utility) { () -> [DiskInfo]? in
            guard let all = try? DiskEnumerator().allDisks() else { return nil }
            return all.filter { SafetyPolicy.default.isSelectable($0) }.sorted { $0.identifier < $1.identifier }
        }.value
        guard let found else { return }
        if found != disks { disks = found }
        if let id = selectedDiskID, !disks.contains(where: { $0.identifier == id }) { selectedDiskID = nil }
        if disks.count == 1, selectedDiskID == nil, let only = disks.first { select(only) }
    }

    // MARK: - Backup: destinazione

    func suggestedName(for disk: DiskInfo) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd-HHmm"
        let prefix = DiskInfoPresentation(disk: disk).looksLikeRaspberry ? "RaspberryPi" : "SD"
        return "\(prefix)-\(fmt.string(from: Date()))"
    }

    /// File finale: nome scelto, senza caratteri vietati e senza sovrascrivere nulla.
    var backupDestination: URL {
        var base = backupName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for ext in [".xz", ".img"] where base.lowercased().hasSuffix(ext) { base = String(base.dropLast(ext.count)) }
        if base.isEmpty { base = "sdclone" }
        let ext = compressBackups ? ".img.xz" : ".img"
        var url = backupFolder.appendingPathComponent(base + ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) && !demo {
            url = backupFolder.appendingPathComponent("\(base) \(n)\(ext)")
            n += 1
        }
        return url
    }

    var freeSpace: UInt64? {
        if demo { return 412_000_000_000 }
        var url = backupFolder
        while !FileManager.default.fileExists(atPath: url.path), url.pathComponents.count > 1 { url.deleteLastPathComponent() }
        guard let n = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage else { return nil }
        return UInt64(n)
    }

    var backupFitsOnDisk: Bool {
        guard let disk = selectedDisk, let free = freeSpace else { return true }
        return backupNeededBytes(for: disk) <= free
    }

    /// Con la compressione l'esito non e' noto in anticipo: si conta prudentemente la meta'.
    func backupNeededBytes(for disk: DiskInfo) -> UInt64 {
        compressBackups ? disk.estimatedUsedBytes / 2 : disk.estimatedUsedBytes
    }

    var canStartBackup: Bool { job == nil && selectedDisk != nil && backupFitsOnDisk }

    /// Posti dove salvare di solito: Documenti, Scrivania e le cartelle di Google Drive sincronizzate sul Mac.
    var quickFolders: [(title: String, url: URL)] {
        let fm = FileManager.default
        var list: [(String, URL)] = [("Documenti › SDClone", BackupLibrary.defaultDirectory()),
                                     ("Scrivania", fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"))]
        let cloud = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/CloudStorage")
        let accounts = ((try? fm.contentsOfDirectory(atPath: cloud.path)) ?? []).filter { $0.hasPrefix("GoogleDrive-") }.sorted()
        for account in accounts {
            let root = cloud.appendingPathComponent(account)
            let email = String(account.dropFirst("GoogleDrive-".count))
            let children = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
            for child in children {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: root.appendingPathComponent(child).path, isDirectory: &isDir), isDir.boolValue {
                    list.append(("Google Drive · \(email) › \(child)", root.appendingPathComponent(child)))
                }
            }
        }
        return list
    }

    func useFolder(_ url: URL) {
        backupFolder = url
        refreshLibrary()
    }

    func chooseBackupFolder() {
        if let url = Panels.chooseFolder(start: backupFolder) {
            backupFolder = url
            refreshLibrary()
        }
    }

    // MARK: - Ripristino: immagine

    func imageSize(_ url: URL) -> UInt64? {
        if demo { return library.first { $0.url == url }.map { $0.uncompressedBytes ?? $0.sizeBytes } }
        if XZFormat.isXZ(url) { return try? XZFormat.uncompressedSize(of: url) }
        guard let n = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return UInt64(n)
    }

    /// Motivo per cui l'immagine scelta non si puo' usare, se ce n'e' uno.
    var restoreProblem: String? {
        guard let url = restoreImage else { return nil }
        guard let size = imageSize(url), size > 0, size % UInt64(PartitionLayout.sectorSize) == 0 else {
            return "Il file non sembra un'immagine disco valida."
        }
        if let disk = selectedDisk, size > disk.sizeBytes {
            return "L'immagine (\(ByteFormat.string(size))) non entra in questa scheda (\(ByteFormat.string(disk.sizeBytes)))."
        }
        return nil
    }

    var canStartRestore: Bool {
        job == nil && restoreImage != nil && selectedDisk != nil && restoreProblem == nil
    }

    func setRestoreImage(_ url: URL) {
        restoreImage = url
        mode = .restore
    }

    func chooseRestoreImage() {
        if let url = Panels.chooseImage(start: backupFolder) { restoreImage = url }
    }

    private static func savedBackupFolder() -> URL {
        guard ProcessInfo.processInfo.environment["SDCLONE_DEMO"] != "1",
              let path = UserDefaults.standard.string(forKey: "backupFolder") else { return BackupLibrary.defaultDirectory() }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func resetBackupFolder() {
        backupFolder = BackupLibrary.defaultDirectory()
        refreshLibrary()
    }

    func showBackupFolder() {
        try? FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(backupFolder)
    }

    /// Un'immagine aperta dal Finder ("Apri con", trascinata sull'icona): si prepara il ripristino, senza avviare nulla.
    func openImage(_ url: URL) {
        guard job == nil else { return }
        restoreImage = url
        mode = .restore
    }

    // MARK: - Ottimizza

    func refreshTools() {
        if demo {
            let missing = ProcessInfo.processInfo.environment["SDCLONE_DEMO_NO_E2FS"] != nil
            e2fsTools = missing ? nil : E2fsTools(directory: URL(fileURLWithPath: "/opt/homebrew/opt/e2fsprogs/sbin"))
        } else {
            e2fsTools = try? E2fsTools.locate()
        }
    }

    func setOptimizeImage(_ url: URL) {
        optimizeImage = url
        mode = .optimize
    }

    func chooseOptimizeImage() {
        if let url = Panels.chooseImage(start: backupFolder) { optimizeImage = url }
    }

    private func analyzeOptimizeImage() {
        optimizeAnalysis = nil
        optimizeAnalysisError = nil
        guard let url = optimizeImage else { return }
        if demo {
            optimizeAnalysis = DemoData.analysis(for: library.first { $0.url == url })
            return
        }
        analyzingImage = true
        let tools = e2fsTools
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<ImageAnalysis, Error> in
                Result { try ImageOptimizer.analyze(url, tools: tools) }
            }.value
            guard optimizeImage == url else { return }   // nel frattempo ne e' stata scelta un'altra
            analyzingImage = false
            switch result {
            case .success(let a): optimizeAnalysis = a
            case .failure(let e): optimizeAnalysisError = "\(e)"
            }
        }
    }

    /// I file che verranno creati accanto all'immagine scelta.
    var optimizePlannedOutputs: [URL] {
        guard let url = optimizeImage else { return [] }
        let p = ImageOptimizer.plannedOutputs(for: url, options: optimizeOptions, in: url.deletingLastPathComponent())
        return [p.xz, p.image].compactMap { $0 }
    }

    /// Motivo per cui non si puo' partire, se c'e'.
    var optimizeProblem: String? {
        let o = optimizeOptions
        if !o.rebuilds && !o.compress { return "Scegli almeno un'operazione." }
        if o.rebuilds && e2fsTools == nil { return "Per ridurre o ripulire servono gli strumenti e2fsprogs." }
        if !o.rebuilds, optimizeAnalysis?.isCompressed == true { return "L'immagine è già compressa: scegli anche Riduci o Pulizia." }
        return nil
    }

    var canStartOptimize: Bool {
        job == nil && optimizeImage != nil && optimizeAnalysis != nil && optimizeProblem == nil
    }

    func startOptimize() {
        guard canStartOptimize, let image = optimizeImage, let analysis = optimizeAnalysis else { return }
        let options = optimizeOptions
        let planned = optimizePlannedOutputs
        let run = JobRun(kind: .optimize, disk: nil, file: planned.first ?? image,
                         expectedBytes: analysis.root.endByte, compressed: options.compress)
        run.optimizeOptions = options
        run.waitingForAuthorization = false
        let urls = beginJob(run)
        if demo {
            jobTask = Task { [weak self] in await self?.simulateOptimize(run, analysis: analysis) }
            return
        }

        let tools = e2fsTools
        jobTask = Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) { () -> ImageOptimizer.Result in
                    var lastReport = Date.distantPast
                    var lastStep: ImageOptimizer.Step?
                    return try ImageOptimizer().run(
                        image: image, options: options, tools: tools,
                        progress: { p in
                            let now = Date()
                            guard p.step != lastStep || now.timeIntervalSince(lastReport) >= 0.25 else { return }
                            lastReport = now
                            lastStep = p.step
                            Task { @MainActor in run.applyOptimize(p) }
                        },
                        isCancelled: { FileManager.default.fileExists(atPath: urls.cancel.path) })
                }.value
                run.file = result.output
                run.optimizeResult = result
                var done = JobStatus(state: .done, phase: .finishing, bytesDone: result.imageBytes,
                                     bytesTotal: result.imageBytes, sha256: result.sha256, outputPath: result.output.path)
                done.outputBytes = result.compressedBytes
                run.apply(done)
                run.conclude(.success)
            } catch TransferError.cancelled {
                run.conclude(.cancelled)
            } catch {
                run.conclude(.failed("\(error)"))
            }
            self?.concluded()
        }
    }

    private static func loadOptimizeOptions() -> ImageOptimizer.Options {
        let d = UserDefaults.standard
        func flag(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) as? Bool ?? fallback }
        return ImageOptimizer.Options(shrink: flag("optimize.shrink", true), clean: flag("optimize.clean", true),
                                      compress: flag("optimize.compress", true), keepUncompressed: flag("optimize.keepImage", false))
    }

    private static func saveOptimizeOptions(_ o: ImageOptimizer.Options) {
        let d = UserDefaults.standard
        d.set(o.shrink, forKey: "optimize.shrink")
        d.set(o.clean, forKey: "optimize.clean")
        d.set(o.compress, forKey: "optimize.compress")
        d.set(o.keepUncompressed, forKey: "optimize.keepImage")
    }

    // MARK: - Archivio

    func refreshLibrary() {
        library = demo ? DemoData.library(in: backupFolder) : BackupLibrary.entries(in: backupFolder)
    }

    func moveToTrash(_ entry: BackupEntry) {
        let fm = FileManager.default
        try? fm.trashItem(at: entry.url, resultingItemURL: nil)
        let sidecar = entry.url.appendingPathExtension("sha256")
        if fm.fileExists(atPath: sidecar.path) { try? fm.trashItem(at: sidecar, resultingItemURL: nil) }
        if restoreImage == entry.url { restoreImage = nil }
        if optimizeImage == entry.url { optimizeImage = nil }
        refreshLibrary()
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Avvio dei lavori

    func startBackup() {
        guard canStartBackup, let disk = selectedDisk else { return }
        let destination = backupDestination
        try? FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        let compress = compressBackups
        launch(JobRun(kind: .backup, disk: disk, file: destination,
                      expectedBytes: disk.estimatedUsedBytes, compressed: compress)) { status, cancel in
            ["backup", disk.identifier, "-o", destination.path] + (compress ? ["--xz"] : []) +
            ["--status-file", status.path, "--cancel-file", cancel.path, "--as-user", "\(getuid())"]
        }
    }

    func startRestore() {
        guard canStartRestore, let disk = selectedDisk, let image = restoreImage else { return }
        launch(JobRun(kind: .restore, disk: disk, file: image, expectedBytes: imageSize(image) ?? 0)) { status, cancel in
            // `--confirm` e' la conferma gia' data nella finestra: l'helper la confronta col disco.
            ["restore", image.path, disk.identifier, "--confirm", disk.identifier,
             "--status-file", status.path, "--cancel-file", cancel.path, "--as-user", "\(getuid())"]
        }
    }

    /// Prepara cartella di lavoro, file di annullamento e blocco dello stop del Mac. Restituisce (stato, annulla).
    private func beginJob(_ run: JobRun) -> (status: URL, cancel: URL) {
        job = run
        showRestoreConfirm = false
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sdclone-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        runDirectory = dir
        let urls = (status: dir.appendingPathComponent("status.json"), cancel: dir.appendingPathComponent("cancel"))
        cancelFile = urls.cancel
        if Preferences.notifyWhenDone { Notifier.requestPermission() }
        // Impedisce lo stop del Mac durante la copia.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                         reason: "SD Clone sta lavorando")
        return urls
    }

    /// Comprime in .xz un backup gia' salvato. Sono file dell'utente: niente password, tutto dentro l'app.
    func startCompress(_ entry: BackupEntry) {
        guard job == nil, !entry.isCompressed else { return }
        let source = entry.url
        let destination = source.appendingPathExtension("xz")
        if !demo && FileManager.default.fileExists(atPath: destination.path) {
            ejectError = "Esiste già «\(destination.lastPathComponent)»: spostalo o eliminalo prima di comprimere di nuovo."
            return
        }
        let run = JobRun(kind: .compress, disk: nil, file: destination, expectedBytes: entry.sizeBytes)
        run.waitingForAuthorization = false
        let urls = beginJob(run)
        if demo {
            jobTask = Task { [weak self] in await self?.simulate(run) }
            return
        }

        let length = entry.sizeBytes
        jobTask = Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) { () -> BackupResult in
                    var lastReport = Date.distantPast
                    return try BackupEngine().run(
                        source: source.path, length: length, destination: destination, compress: true,
                        progress: { p in
                            let now = Date()
                            guard now.timeIntervalSince(lastReport) >= 0.25 else { return }
                            lastReport = now
                            let status = JobStatus(state: .running, phase: .copying).updating(p, phase: .copying)
                            Task { @MainActor in run.apply(status) }
                        },
                        isCancelled: { FileManager.default.fileExists(atPath: urls.cancel.path) })
                }.value

                // Se l'originale aveva uno SHA256 registrato, quello dei dati compressi deve coincidere.
                if let known = BackupLibrary.sha256(forImage: source), known != result.sha256 {
                    try? FileManager.default.removeItem(at: destination)
                    run.conclude(.failed("Lo SHA256 dei dati non coincide con quello registrato per «\(source.lastPathComponent)»: l'originale potrebbe essere stato modificato o danneggiato. Il file compresso è stato eliminato."))
                } else {
                    let sidecar = destination.appendingPathExtension("sha256")
                    try? "\(result.sha256)  \(source.lastPathComponent)\n".write(to: sidecar, atomically: true, encoding: .utf8)
                    var done = JobStatus(state: .done, phase: .finishing, bytesDone: length, bytesTotal: length,
                                         sha256: result.sha256, outputPath: destination.path)
                    done.outputBytes = result.outputBytes
                    run.apply(done)
                    run.conclude(.success)
                }
            } catch TransferError.cancelled {
                run.conclude(.cancelled)
            } catch {
                run.conclude(.failed("\(error)"))
            }
            self?.concluded()
        }
    }

    private func launch(_ run: JobRun, makeArguments: (URL, URL) -> [String]) {
        let (statusURL, cancelURL) = beginJob(run)

        if demo {
            jobTask = Task { [weak self] in await self?.simulate(run) }
            return
        }
        guard let helper = PrivilegedShell.helperURL() else {
            run.conclude(.failed("Il componente «sdclone» non è stato trovato dentro l'app."))
            endActivity()
            return
        }
        let arguments = [helper.path] + makeArguments(statusURL, cancelURL)
        jobTask = Task { [weak self] in
            let poller = Task {
                while !Task.isCancelled {
                    if let s = JobStatus.read(from: statusURL) { run.apply(s) }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            let result = await PrivilegedShell.run(arguments: arguments,
                                                   prompt: "SD Clone deve accedere direttamente alla scheda SD.")
            poller.cancel()
            let final = JobStatus.read(from: statusURL)
            if let final { run.apply(final) }
            self?.finish(run, shell: result, final: final)
        }
    }

    private func finish(_ run: JobRun, shell: PrivilegedShell.Result, final: JobStatus?) {
        if case .authCancelled = shell {   // ha chiuso la finestra della password: si torna indietro senza errori
            dismissJob()
            return
        }
        switch final?.state {
        case .done?: run.conclude(.success)
        case .cancelled?: run.conclude(.cancelled)
        case .failed?: run.conclude(.failed(final?.message ?? "Errore sconosciuto."))
        default:
            if run.cancelRequested {
                run.conclude(.cancelled)
            } else if case .failed(let message) = shell {
                run.conclude(.failed(message))
            } else {
                run.conclude(.failed("L'operazione si è interrotta in modo inatteso."))
            }
        }
        concluded()
    }

    private func concluded() {
        endActivity()
        refreshLibrary()
        NSApp.requestUserAttention(.informationalRequest)
        if let run = job, let outcome = run.outcome {
            if Preferences.playSound { NSSound(named: outcome == .success ? "Glass" : "Basso")?.play() }
            if Preferences.notifyWhenDone && !NSApp.isActive { Notifier.post(run: run, outcome: outcome) }
        }
    }

    private func endActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    func cancelJob() {
        guard let run = job, !run.isFinished, !run.waitingForAuthorization else { return }
        run.cancelRequested = true
        if let cancelFile { FileManager.default.createFile(atPath: cancelFile.path, contents: nil) }
    }

    /// Chiude la schermata dell'esito e torna alla selezione.
    func dismissJob() {
        let finishedRestore = job?.kind == .restore && job?.outcome == .success
        jobTask?.cancel()
        jobTask = nil
        job = nil
        endActivity()
        if let runDirectory { try? FileManager.default.removeItem(at: runDirectory) }
        runDirectory = nil
        cancelFile = nil
        if finishedRestore { selectedDiskID = nil }
        refreshLibrary()
        Task { await refreshDisks() }
    }

    /// Se c'e' un lavoro in corso: chiede l'annullamento e ritorna true.
    var hasRunningJob: Bool { job.map { !$0.isFinished } ?? false }

    // MARK: - Espulsione

    /// Smonta ed espelle la scheda (non serve root). Se qualcosa la sta usando, `diskutil` lo dice e lo mostriamo.
    func eject(_ disk: DiskInfo) {
        guard !hasRunningJob, !ejecting.contains(disk.identifier) else { return }
        ejecting.insert(disk.identifier)
        Task { [weak self] in
            var failure: String?
            if self?.demo == true {
                try? await Task.sleep(for: .seconds(1))
            } else {
                failure = await Task.detached { () -> String? in
                    do { try DiskControl.eject(disk); return nil } catch { return "\(error)" }
                }.value
            }
            guard let self else { return }
            ejecting.remove(disk.identifier)
            if let failure {
                ejectError = "Non sono riuscito a espellere \(disk.identifier). Probabilmente un programma la sta usando: chiudilo e riprova.\n\n\(failure)"
            } else if demo {
                disks.removeAll { $0.identifier == disk.identifier }
                if selectedDiskID == disk.identifier { selectedDiskID = nil }
            } else {
                await refreshDisks()
            }
        }
    }

    // MARK: - Demo

    private func simulate(_ run: JobRun) async {
        let factor = Double(ProcessInfo.processInfo.environment["SDCLONE_DEMO_SPEED"] ?? "") ?? 6
        let total = max(run.expectedBytes, 1_000_000)
        var status = JobStatus(state: .starting, phase: .preparing, bytesTotal: total)

        if run.kind != .compress { try? await Task.sleep(for: .seconds(1.4)) }   // finta richiesta di password
        run.apply(status)
        try? await Task.sleep(for: .seconds(0.9))

        let phases: [JobStatus.Phase] = run.kind == .restore ? [.copying, .verifying] : [.copying]
        for phase in phases {
            var done: UInt64 = 0
            var tick = 0
            while done < total {
                if Task.isCancelled { return }
                if run.cancelRequested {
                    run.conclude(.cancelled)
                    concluded()
                    return
                }
                tick += 1
                let wobble = 1 + 0.22 * sin(Double(tick) / 7) + Double.random(in: -0.06...0.06)
                let speed = (phase == .verifying ? 80e6 : 41e6) * factor * wobble
                done = min(total, done + UInt64(speed * 0.1))
                status.state = .running
                status.phase = phase
                status.bytesDone = done
                status.bytesPerSecond = speed
                status.secondsRemaining = Double(total - done) / speed
                run.apply(status)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        let fail = ProcessInfo.processInfo.environment["SDCLONE_DEMO_FAIL"]
        if fail == "access" {
            status.needsFullDiskAccess = true
            run.apply(status)
            run.conclude(.failed("macOS ha bloccato l'accesso diretto a /dev/rdisk4."))
        } else if fail == "1" {
            run.conclude(.failed("errore di lettura al byte 9437184000: Input/output error"))
        } else {
            status.sha256 = "9f3a4c1de07b58a2c6e18b30f4d97a15e2b0c8d364a7f19e5bd20c8a73f61e04"
            if run.kind == .compress || run.compressed { status.outputBytes = total / 4 }
            run.apply(status)
            run.conclude(.success)
        }
        concluded()
    }

    private func simulateOptimize(_ run: JobRun, analysis: ImageAnalysis) async {
        let o = run.optimizeOptions
        let finalBytes = o.shrink ? (analysis.estimatedShrunkBytes ?? analysis.imageBytes) : analysis.imageBytes
        var plan: [(ImageOptimizer.Step, UInt64)] = []
        if o.rebuilds { plan += [(.extracting, analysis.root.endByte), (.checking, 0)] }
        if o.clean { plan.append((.cleaning, 0)) }
        if o.shrink { plan.append((.shrinking, 0)) }
        if o.rebuilds { plan += [(.assembling, finalBytes - analysis.root.startByte), (.verifying, 0)] }
        if o.compress { plan.append((.compressing, finalBytes)) }
        let factor = Double(ProcessInfo.processInfo.environment["SDCLONE_DEMO_SPEED"] ?? "") ?? 6
        for (step, total) in plan {
            if total == 0 {
                run.applyOptimize(.init(step: step, transfer: nil))
                try? await Task.sleep(for: .seconds(1.2))
                continue
            }
            var tracker = ProgressTracker(total: total)
            var done: UInt64 = 0, t = 0.0
            while done < total {
                if Task.isCancelled { return }
                if run.cancelRequested { run.conclude(.cancelled); concluded(); return }
                let speed = (step == .compressing ? 90e6 : 700e6) * factor * (1 + 0.2 * sin(t * 3))
                done = min(total, done + UInt64(speed * 0.1))
                t += 0.1
                run.applyOptimize(.init(step: step, transfer: tracker.update(bytesDone: done, now: t)))
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        let output = run.file
        run.optimizeResult = ImageOptimizer.Result(
            output: output, files: [output], originalBytes: analysis.imageBytes, imageBytes: finalBytes,
            compressedBytes: o.compress ? finalBytes / 3 : nil,
            sha256: "acabc0d8b9d0633fee25b512f8b2df088dd190b89e0288b421e998d8309407c7",
            removedFiles: o.clean ? ["/home/pi/.bash_history", "/root/.bash_history"] : [])
        var done = JobStatus(state: .done, phase: .finishing, bytesDone: finalBytes, bytesTotal: finalBytes,
                             sha256: run.optimizeResult?.sha256)
        done.outputBytes = run.optimizeResult?.compressedBytes
        run.apply(done)
        run.conclude(.success)
        concluded()
    }

    /// Stati di partenza per provare l'interfaccia: `SDCLONE_DEMO_STATE`.
    func applyDemoState() {
        guard demo, !demoStateApplied, let state = ProcessInfo.processInfo.environment["SDCLONE_DEMO_STATE"] else { return }
        demoStateApplied = true
        let sd = disks.first
        switch state {
        case "backup": if let sd { select(sd) }
        case "backup-run": if let sd { select(sd); startBackup() }
        case "restore":
            mode = .restore
            restoreImage = library.first?.url
            if let sd { select(sd) }
        case "restore-run":
            mode = .restore
            restoreImage = library.first?.url
            if let sd { select(sd); startRestore() }
        case "confirm":
            mode = .restore
            restoreImage = library.first?.url
            if let sd { select(sd); showRestoreConfirm = true }
        case "library": mode = .library
        case "optimize":
            mode = .optimize
            optimizeImage = library.first?.url
        case "optimize-run", "optimize-done":
            mode = .optimize
            optimizeImage = library.first?.url
            startOptimize()
        case "compress-run":
            mode = .library
            if let first = library.first(where: { !$0.isCompressed }) { startCompress(first) }
        default: break
        }
    }
}
