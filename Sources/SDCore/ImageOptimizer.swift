import Foundation

/// Riduce, ripulisce e comprime un'immagine di Raspberry Pi (versione Swift di `scripts/sdimg.sh shrink`).
///
/// Regole fisse, come nello script:
/// - l'immagine di partenza non si tocca mai e nessun file esistente viene sovrascritto;
/// - la partizione ext4 viene estratta in un file a parte, lavorata li' e ricomposta: mai `resize2fs file?offset=N`
///   per modificare (con l'offset tronca/estende il file ignorandolo e rovina la coda). `?offset=` solo in sola lettura;
/// - il risultato viene controllato con `e2fsck -fn` prima di essere messo al suo posto.
public struct ImageOptimizer {
    public struct Options: Equatable, Sendable {
        /// Porta la partizione Linux al minimo (stile PiShrink).
        public var shrink: Bool
        /// Toglie le cronologie (shell, python, less, vim...) da /root e dalle cartelle in /home.
        public var clean: Bool
        /// Produce un `.img.xz`.
        public var compress: Bool
        /// Con `compress`: conserva anche il `.img` non compresso.
        public var keepUncompressed: Bool

        public init(shrink: Bool = true, clean: Bool = false, compress: Bool = true, keepUncompressed: Bool = false) {
            self.shrink = shrink
            self.clean = clean
            self.compress = compress
            self.keepUncompressed = keepUncompressed
        }

        /// Serve estrarre e ricomporre la partizione (altrimenti si tratta solo di comprimere).
        public var rebuilds: Bool { shrink || clean }
        public var writesImage: Bool { !compress || keepUncompressed }
    }

    public enum Step: String, CaseIterable, Sendable {
        case extracting, checking, cleaning, shrinking, assembling, verifying, compressing
    }

    public struct Progress: Sendable {
        public let step: Step
        /// Nil per i passi di durata ignota (e2fsck, resize2fs, debugfs).
        public let transfer: TransferProgress?

        public init(step: Step, transfer: TransferProgress?) {
            self.step = step
            self.transfer = transfer
        }
    }

    public struct Result: Equatable, Sendable {
        /// Il file principale prodotto (il `.img.xz` se compresso).
        public let output: URL
        /// Tutti i file prodotti, senza i `.sha256`.
        public let files: [URL]
        public let originalBytes: UInt64
        /// Dimensione dell'immagine risultante (non compressa).
        public let imageBytes: UInt64
        public let compressedBytes: UInt64?
        /// SHA256 dell'immagine risultante non compressa (scritto nei `.sha256`).
        public let sha256: String
        /// Percorsi tolti dalla pulizia, dentro il filesystem dell'immagine.
        public let removedFiles: [String]

        public init(output: URL, files: [URL], originalBytes: UInt64, imageBytes: UInt64, compressedBytes: UInt64?,
                    sha256: String, removedFiles: [String]) {
            self.output = output
            self.files = files
            self.originalBytes = originalBytes
            self.imageBytes = imageBytes
            self.compressedBytes = compressedBytes
            self.sha256 = sha256
            self.removedFiles = removedFiles
        }
    }

    /// File considerati "cronologie" dalla pulizia.
    public static let historyFiles: Set<String> = [
        ".bash_history", ".zsh_history", ".python_history", ".lesshst", ".viminfo", ".mysql_history",
        ".psql_history", ".sqlite_history", ".node_repl_history", ".wget-hsts",
    ]

    public var blockSize: Int

    public init(blockSize: Int = 4 * 1024 * 1024) {
        self.blockSize = blockSize
    }

    // MARK: - Analisi

    /// Legge la tabella delle partizioni (anche da un `.img.xz`, decomprimendo solo l'inizio) e, per un `.img`
    /// grezzo con e2fsprogs disponibile, stima la dimensione minima della partizione Linux (in sola lettura).
    public static func analyze(_ image: URL, tools: E2fsTools? = try? E2fsTools.locate()) throws -> ImageAnalysis {
        let compressed = try XZFormat.checkXZ(image.path)
        let imageBytes = compressed ? try XZFormat.uncompressedSize(of: image) : try BlockIO.fileSize(image.path)
        let reader: SequentialReader = compressed ? try XZFileReader(path: image.path) : try RawFileReader(path: image.path)
        var header = [UInt8](repeating: 0, count: 512)
        guard try reader.readFully(&header, 512) == 512 else { throw OptimizeError.notAnImage("il file e' troppo corto") }
        let partitions = try MBR.partitions(Data(header))
        let root = try MBR.optimizableRoot(partitions, imageBytes: imageBytes)

        var minimum: UInt64?
        if !compressed, let tools {
            minimum = try? tools.estimatedMinimumBytes(of: image.path, offset: root.startByte)
        }
        return ImageAnalysis(imageBytes: imageBytes, isCompressed: compressed, partitions: partitions, root: root,
                             minimumRootBytes: minimum)
    }

    // MARK: - Nomi

    /// "Foto.img" / "Foto.img.xz" -> "Foto".
    public static func baseName(of image: URL) -> String {
        var name = image.lastPathComponent
        for ext in [".xz", ".img"] where name.lowercased().hasSuffix(ext) { name = String(name.dropLast(ext.count)) }
        return name
    }

    /// I file che verranno creati in `directory`, con un numero aggiunto se il nome e' gia' preso (mai sovrascrivere).
    public static func plannedOutputs(for image: URL, options: Options, in directory: URL) -> (image: URL?, xz: URL?) {
        let fm = FileManager.default
        let tag = options.shrink ? ".min" : options.clean ? ".clean" : ""
        let base = baseName(of: image) + tag
        var n = 1
        while true {
            let stem = n == 1 ? base : "\(base) \(n)"
            let img = directory.appendingPathComponent(stem + ".img")
            let xz = directory.appendingPathComponent(stem + ".img.xz")
            let wanted = [options.writesImage ? img : nil, options.compress ? xz : nil].compactMap { $0 }
            let taken = wanted.contains { fm.fileExists(atPath: $0.path) || fm.fileExists(atPath: $0.path + ".sha256") }
                || wanted.contains { $0.standardizedFileURL == image.standardizedFileURL }
            if !taken { return (options.writesImage ? img : nil, options.compress ? xz : nil) }
            n += 1
        }
    }

    // MARK: - Lavoro

    public func run(image: URL, options: Options, outputDirectory: URL? = nil,
                    tools: E2fsTools? = nil,
                    progress: (Progress) -> Void = { _ in },
                    isCancelled: @escaping () -> Bool = { false }) throws -> Result {
        guard options.rebuilds || options.compress else { throw OptimizeError.nothingToDo }
        let analysis = try Self.analyze(image, tools: nil)
        if !options.rebuilds && analysis.isCompressed { throw OptimizeError.nothingToDo }
        let tools = options.rebuilds ? try tools ?? E2fsTools.locate() : nil

        let directory = outputDirectory ?? image.deletingLastPathComponent()
        let planned = Self.plannedOutputs(for: image, options: options, in: directory)

        // Cartella di lavoro sul disco interno, fuori da cartelle sincronizzate (Google Drive) e dall'Archivio.
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("sdclone-optimize-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let keptBytes = analysis.root.endByte
        try Self.requireSpace(keptBytes * 2 + (256 << 20), in: work)
        if !Self.sameVolume(work, directory) { try Self.requireSpace(keptBytes, in: directory) }

        var removed: [String] = []
        var assembled: URL
        var imageBytes: UInt64

        if options.rebuilds, let tools {
            let out = work.appendingPathComponent("out.img")
            let part = work.appendingPathComponent("part.img")
            try extract(image, compressed: analysis.isCompressed, root: analysis.root, header: out, partition: part,
                        progress: progress, isCancelled: isCancelled)

            progress(Progress(step: .checking, transfer: nil))
            try tools.repair(part.path, isCancelled: isCancelled)

            if options.clean {
                progress(Progress(step: .cleaning, transfer: nil))
                removed = try tools.removeHistories(part.path, names: Self.historyFiles, isCancelled: isCancelled)
                if !removed.isEmpty { try tools.repair(part.path, isCancelled: isCancelled) }
            }

            var sectors = analysis.root.sectors
            if options.shrink {
                progress(Progress(step: .shrinking, transfer: nil))
                let fsBytes = try tools.shrinkToMinimum(part.path, isCancelled: isCancelled)
                let minimumSectors = (fsBytes / 512 + 2047) / 2048 * 2048   // arrotondato al MiB
                sectors = min(analysis.root.sectors, minimumSectors)
            }
            guard truncate(part.path, off_t(sectors * 512)) == 0 else { throw TransferError.writeFailed(errno: errno) }

            try assemble(partition: part, into: out, root: analysis.root, newSectors: sectors,
                         progress: progress, isCancelled: isCancelled)
            try? FileManager.default.removeItem(at: part)

            progress(Progress(step: .verifying, transfer: nil))
            imageBytes = analysis.root.startByte + sectors * 512
            guard try BlockIO.fileSize(out.path) == imageBytes else { throw OptimizeError.verificationFailed("dimensione del file inattesa") }
            try tools.checkReadOnly(out.path, offset: analysis.root.startByte, isCancelled: isCancelled)
            assembled = out
        } else {
            assembled = image   // solo compressione di un .img grezzo
            imageBytes = analysis.imageBytes
        }

        // SHA256 dell'immagine finale: lo calcola la compressione oppure una lettura apposita.
        var sha: String
        var compressedBytes: UInt64?
        var files: [(from: URL, to: URL)] = []
        if options.compress, let xzURL = planned.xz {
            let xzWork = work.appendingPathComponent("out.img.xz")
            let r = try BackupEngine(blockSize: blockSize).run(
                source: assembled.path, length: imageBytes, destination: xzWork, compress: true,
                progress: { progress(Progress(step: .compressing, transfer: $0)) }, isCancelled: isCancelled)
            sha = r.sha256
            compressedBytes = r.outputBytes
            files.append((xzWork, xzURL))
        } else {
            let fd = open(assembled.path, O_RDONLY)
            guard fd >= 0 else { throw TransferError.openFailure(assembled.path, errno) }
            defer { close(fd) }
            sha = try BlockIO.sha256(fd: fd, length: imageBytes, blockSize: blockSize,
                                     progress: { progress(Progress(step: .verifying, transfer: $0)) },
                                     isCancelled: isCancelled)
        }
        // Se l'originale e' gia' identico nei dati (solo compressione), lo SHA registrato deve coincidere.
        if !options.rebuilds, let known = BackupLibrary.sha256(forImage: image), known != sha {
            throw OptimizeError.verificationFailed("lo SHA256 dei dati non coincide con quello registrato per \(image.lastPathComponent)")
        }
        if let imgURL = planned.image, options.writesImage, assembled != image {
            files.append((assembled, imgURL))
        }

        if isCancelled() { throw TransferError.cancelled }
        var placed: [URL] = []
        do {
            for f in files {
                try Self.place(f.from, at: f.to)
                placed.append(f.to)
                let rawName = f.to.lastPathComponent.hasSuffix(".xz") ? String(f.to.lastPathComponent.dropLast(3)) : f.to.lastPathComponent
                try "\(sha)  \(rawName)\n".write(to: f.to.appendingPathExtension("sha256"), atomically: true, encoding: .utf8)
                placed.append(f.to.appendingPathExtension("sha256"))
            }
        } catch {
            for url in placed { try? FileManager.default.removeItem(at: url) }
            throw error
        }

        let outputs = files.map(\.to)
        return Result(output: planned.xz ?? planned.image ?? outputs[0], files: outputs,
                      originalBytes: analysis.imageBytes, imageBytes: imageBytes,
                      compressedBytes: compressedBytes, sha256: sha, removedFiles: removed)
    }

    /// Copia l'inizio dell'immagine (MBR, boot) in `header` e la partizione Linux in `partition`.
    private func extract(_ image: URL, compressed: Bool, root: MBRPartition, header: URL, partition: URL,
                         progress: (Progress) -> Void, isCancelled: () -> Bool) throws {
        let reader: SequentialReader = compressed ? try XZFileReader(path: image.path) : try RawFileReader(path: image.path)
        let total = root.endByte
        var tracker = ProgressTracker(total: total)
        let clock = Stopwatch()
        var buffer = [UInt8](repeating: 0, count: blockSize)
        var done: UInt64 = 0

        for (url, end) in [(header, root.startByte), (partition, total)] {
            let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
            guard fd >= 0 else { throw TransferError.cannotCreateDestination(url.path, errno) }
            defer { close(fd) }
            while done < end {
                if isCancelled() { throw TransferError.cancelled }
                let want = Int(min(UInt64(blockSize), end - done))
                let got = try reader.readFully(&buffer, want)
                guard got == want else { throw TransferError.shortRead(expected: total, got: done + UInt64(got)) }
                try BlockIO.writeFully(fd, buffer, count: got)
                done += UInt64(got)
                progress(Progress(step: .extracting, transfer: tracker.update(bytesDone: done, now: clock.seconds())))
            }
        }
    }

    /// Accoda la partizione all'inizio dell'immagine e aggiorna la sua dimensione nella tabella MBR.
    private func assemble(partition: URL, into out: URL, root: MBRPartition, newSectors: UInt64,
                          progress: (Progress) -> Void, isCancelled: () -> Bool) throws {
        let length = newSectors * 512
        let src = open(partition.path, O_RDONLY)
        guard src >= 0 else { throw TransferError.openFailure(partition.path, errno) }
        defer { close(src) }
        let dst = open(out.path, O_RDWR)
        guard dst >= 0 else { throw TransferError.openFailure(out.path, errno, writing: true) }
        defer { close(dst) }
        guard lseek(dst, off_t(root.startByte), SEEK_SET) >= 0 else { throw TransferError.writeFailed(errno: errno) }

        var tracker = ProgressTracker(total: length)
        let clock = Stopwatch()
        var buffer = [UInt8](repeating: 0, count: blockSize)
        var done: UInt64 = 0
        while done < length {
            if isCancelled() { throw TransferError.cancelled }
            let want = Int(min(UInt64(blockSize), length - done))
            let got = try BlockIO.readFully(src, &buffer, want, offset: done)
            guard got == want else { throw TransferError.shortRead(expected: length, got: done + UInt64(got)) }
            try BlockIO.writeFully(dst, buffer, count: got)
            done += UInt64(got)
            progress(Progress(step: .assembling, transfer: tracker.update(bytesDone: done, now: clock.seconds())))
        }
        guard ftruncate(dst, off_t(root.startByte + length)) == 0 else { throw TransferError.writeFailed(errno: errno) }

        var mbr = [UInt8](repeating: 0, count: 512)
        guard try BlockIO.readFully(dst, &mbr, 512, offset: 0) == 512 else { throw OptimizeError.notAnImage("MBR illeggibile") }
        try MBR.setSectors(&mbr, partition: root.number, sectors: newSectors)
        guard pwrite(dst, mbr, 512, 0) == 512, fsync(dst) == 0 else { throw TransferError.writeFailed(errno: errno) }
    }

    // MARK: - File e spazio

    /// Sposta `from` in `to` senza mai sovrascrivere. Fra dischi diversi copia su un file nascosto e poi rinomina,
    /// cosi' nella cartella (magari sincronizzata con Drive) non compare mai un file a meta' col nome definitivo.
    static func place(_ from: URL, at to: URL) throws {
        if renamex_np(from.path, to.path, UInt32(RENAME_EXCL)) == 0 { return }
        let code = errno
        if code == EEXIST { throw OptimizeError.wouldOverwrite(to.path) }
        guard code == EXDEV else { throw TransferError.cannotCreateDestination(to.path, code) }
        let partial = to.deletingLastPathComponent().appendingPathComponent(".\(to.lastPathComponent).partial")
        try? FileManager.default.removeItem(at: partial)
        do {
            try FileManager.default.copyItem(at: from, to: partial)
            guard renamex_np(partial.path, to.path, UInt32(RENAME_EXCL)) == 0 else {
                throw errno == EEXIST ? OptimizeError.wouldOverwrite(to.path) : TransferError.cannotCreateDestination(to.path, errno)
            }
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    static func requireSpace(_ bytes: UInt64, in directory: URL) throws {
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let avail = values?.volumeAvailableCapacityForImportantUsage, UInt64(avail) < bytes {
            throw TransferError.insufficientSpace(needed: bytes, available: UInt64(avail))
        }
    }

    static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        var sa = stat(), sb = stat()
        guard stat(a.path, &sa) == 0, stat(b.path, &sb) == 0 else { return false }
        return sa.st_dev == sb.st_dev
    }
}

// MARK: - Analisi

public struct ImageAnalysis: Equatable, Sendable {
    /// Dimensione dell'immagine (decompressa, se `.xz`).
    public let imageBytes: UInt64
    public let isCompressed: Bool
    public let partitions: [MBRPartition]
    /// La partizione Linux finale, quella che si riduce.
    public let root: MBRPartition
    /// Minimo stimato da `resize2fs -P` (solo per un `.img` grezzo).
    public let minimumRootBytes: UInt64?

    public init(imageBytes: UInt64, isCompressed: Bool, partitions: [MBRPartition], root: MBRPartition, minimumRootBytes: UInt64?) {
        self.imageBytes = imageBytes
        self.isCompressed = isCompressed
        self.partitions = partitions
        self.root = root
        self.minimumRootBytes = minimumRootBytes
    }

    /// Dimensione prevista dell'immagine ridotta (stessa regola di `run`: partizione arrotondata al MiB).
    public var estimatedShrunkBytes: UInt64? {
        minimumRootBytes.map { root.startByte + min(root.sectors, ($0 / 512 + 2047) / 2048 * 2048) * 512 }
    }
}

// MARK: - Tabella MBR

public struct MBRPartition: Equatable, Sendable {
    public let number: Int
    public let type: UInt8
    public let startSector: UInt64
    public let sectors: UInt64

    public init(number: Int, type: UInt8, startSector: UInt64, sectors: UInt64) {
        self.number = number
        self.type = type
        self.startSector = startSector
        self.sectors = sectors
    }

    public var startByte: UInt64 { startSector * 512 }
    public var sizeBytes: UInt64 { sectors * 512 }
    public var endByte: UInt64 { (startSector + sectors) * 512 }

    public var isLinux: Bool { type == 0x83 }

    /// Nome del tipo come lo scrive `diskutil` (serve all'app per riusare gli stessi colori delle schede).
    public var diskutilContent: String {
        switch type {
        case 0x0B, 0x0C: return "Windows_FAT_32"
        case 0x01, 0x04, 0x06, 0x0E: return "Windows_FAT_16"
        case 0x83: return "Linux"
        case 0x82: return "Linux_Swap"
        default: return String(format: "0x%02X", type)
        }
    }
}

public enum MBR {
    public static func partitions(_ header: Data) throws -> [MBRPartition] {
        guard header.count >= 512 else { throw OptimizeError.notAnImage("intestazione troppo corta") }
        let h = [UInt8](header.prefix(512))
        guard h[510] == 0x55, h[511] == 0xAA else {
            throw OptimizeError.notAnImage("manca la tabella delle partizioni MBR (firma 55AA)")
        }
        var list: [MBRPartition] = []
        for i in 0..<4 {
            let e = 446 + i * 16
            let type = h[e + 4]
            guard type != 0 else { continue }
            if type == 0xEE { throw OptimizeError.unsupported("tabella GPT: si gestiscono solo le immagini MBR di Raspberry Pi") }
            let start = UInt64(le32(h, e + 8)), count = UInt64(le32(h, e + 12))
            if count > 0 { list.append(MBRPartition(number: i + 1, type: type, startSector: start, sectors: count)) }
        }
        guard !list.isEmpty else { throw OptimizeError.notAnImage("la tabella delle partizioni e' vuota") }
        return list
    }

    /// L'ultima partizione deve essere Linux, allineata a 4 KiB e dentro l'immagine; niente partizioni estese.
    public static func optimizableRoot(_ partitions: [MBRPartition], imageBytes: UInt64) throws -> MBRPartition {
        if partitions.contains(where: { [0x05, 0x0F, 0x85].contains($0.type) }) {
            throw OptimizeError.unsupported("partizioni estese non supportate")
        }
        guard let root = partitions.max(by: { $0.startSector < $1.startSector }) else {
            throw OptimizeError.notAnImage("nessuna partizione")
        }
        guard root.isLinux else {
            throw OptimizeError.unsupported(String(format: "l'ultima partizione non e' Linux (tipo 0x%02X)", root.type))
        }
        guard partitions.allSatisfy({ $0 == root || $0.endByte <= root.startByte }) else {
            throw OptimizeError.unsupported("le partizioni si sovrappongono")
        }
        guard root.startSector % 8 == 0, root.sectors % 8 == 0 else {
            throw OptimizeError.unsupported("la partizione Linux non e' allineata a 4 KiB")
        }
        guard root.endByte <= imageBytes else {
            throw OptimizeError.notAnImage("la partizione Linux finisce oltre la fine del file (immagine troncata?)")
        }
        return root
    }

    public static func setSectors(_ mbr: inout [UInt8], partition number: Int, sectors: UInt64) throws {
        guard (1...4).contains(number), sectors <= UInt64(UInt32.max), mbr.count >= 512 else {
            throw OptimizeError.unsupported("valori MBR fuori limite")
        }
        let e = 446 + (number - 1) * 16 + 12
        let v = UInt32(sectors)
        for i in 0..<4 { mbr[e + i] = UInt8(truncatingIfNeeded: v >> (8 * UInt32(i))) }
    }

    private static func le32(_ h: [UInt8], _ o: Int) -> UInt32 {
        UInt32(h[o]) | UInt32(h[o + 1]) << 8 | UInt32(h[o + 2]) << 16 | UInt32(h[o + 3]) << 24
    }
}

// MARK: - Errori

public enum OptimizeError: Error, CustomStringConvertible, Equatable {
    case missingE2fsprogs
    case notAnImage(String)
    case unsupported(String)
    case nothingToDo
    case toolFailed(tool: String, code: Int32, output: String)
    case verificationFailed(String)
    case wouldOverwrite(String)

    public var description: String {
        switch self {
        case .missingE2fsprogs:
            return "servono gli strumenti e2fsprogs (resize2fs, e2fsck, debugfs). Installali con:  brew install e2fsprogs"
        case .notAnImage(let m): return "il file non sembra un'immagine di Raspberry Pi: \(m)"
        case .unsupported(let m): return "immagine non supportata: \(m)"
        case .nothingToDo: return "nessuna operazione scelta (o immagine gia' compressa senza altro da fare)"
        case .toolFailed(let t, let c, let o):
            let tail = o.split(separator: "\n").suffix(6).joined(separator: "\n")
            return "\(t) ha fallito (codice \(c))" + (tail.isEmpty ? "" : ":\n\(tail)")
        case .verificationFailed(let m): return "verifica del risultato fallita: \(m)"
        case .wouldOverwrite(let p): return "\(p) esiste gia': non lo sovrascrivo"
        }
    }
}
