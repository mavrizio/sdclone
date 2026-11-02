import SwiftUI
import SDCore

/// Come mostrare un `DiskInfo` all'utente: titoli, sottotitoli e colori.
struct DiskInfoPresentation {
    let disk: DiskInfo

    var looksLikeRaspberry: Bool {
        let names = disk.volumeNames.map { $0.lowercased() }
        return names.contains("bootfs") || names.contains("rootfs") || names.contains("boot")
    }

    var sizeLabel: String { ByteFormat.string(disk.sizeBytes) }

    /// Etichetta corta per la scheda disegnata ("62 GB").
    var shortSize: String {
        let gb = Double(disk.sizeBytes) / 1_000_000_000
        return gb >= 1 ? String(format: "%.0f GB", gb.rounded()) : ByteFormat.string(disk.sizeBytes)
    }

    var title: String {
        disk.volumeNames.isEmpty ? "Scheda senza nome" : disk.volumeNames.joined(separator: " · ")
    }

    var subtitle: String { "\(sizeLabel) · \(disk.mediaName)" }

    var cardStyle: SDCardView.Style { looksLikeRaspberry ? .raspberry : .graphite }
}

extension PartitionInfo {
    var color: Color {
        switch content {
        case "Windows_FAT_32", "Windows_FAT_16", "DOS_FAT_32": return Color(red: 0.18, green: 0.74, blue: 0.86)
        case "Linux": return Color(red: 1.0, green: 0.60, blue: 0.20)
        case "Apple_APFS", "Apple_HFS": return Color(red: 0.55, green: 0.40, blue: 0.95)
        default: return Color(red: 0.55, green: 0.60, blue: 0.70)
        }
    }

    var displayName: String { name.isEmpty ? kindLabel : name }
}
