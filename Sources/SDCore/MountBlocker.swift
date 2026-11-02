import Foundation
import DiskArbitration

/// Impedisce a macOS di montare i volumi di un disco finche' l'oggetto resta vivo.
/// Serve durante il ripristino: appena chiusa la scrittura macOS rilegge la nuova tabella delle partizioni e monta
/// bootfs e rootfs (con extFS di Paragon anche in scrittura), che scrivono subito `.fseventsd`, superblocco ecc.:
/// la scheda non e' piu' identica all'immagine e la verifica fallisce. Con il veto la scheda resta intatta fino
/// all'espulsione. Funziona per qualsiasi montaggio che passa da DiskArbitration (automatico, Finder, `diskutil`).
public final class MountBlocker {
    private let session: DASession
    private let target: Unmanaged<NSString>

    private static let approval: DADiskMountApprovalCallback = { disk, context in
        guard let context else { return nil }
        let target = Unmanaged<NSString>.fromOpaque(context).takeUnretainedValue() as String
        guard MountBlocker.wholeDiskName(of: disk) == target else { return nil }
        let reason = "SD Clone sta scrivendo questa scheda" as CFString
        return Unmanaged.passRetained(DADissenterCreate(kCFAllocatorDefault, DAReturn(kDAReturnBusy), reason))
    }

    /// `wholeDisk` e' il nome BSD del disco intero ("disk4"): si bloccano tutte le sue partizioni.
    public init?(wholeDisk: String) {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return nil }
        self.session = session
        target = Unmanaged.passRetained(wholeDisk as NSString)
        DASessionSetDispatchQueue(session, DispatchQueue(label: "sdclone.mount-blocker"))
        DARegisterDiskMountApprovalCallback(session, nil, Self.approval, target.toOpaque())
    }

    deinit {
        DAUnregisterCallback(session, unsafeBitCast(Self.approval, to: UnsafeMutableRawPointer.self), target.toOpaque())
        DASessionSetDispatchQueue(session, nil)
        target.release()
    }

    static func wholeDiskName(of disk: DADisk) -> String? {
        guard let whole = DADiskCopyWholeDisk(disk), let name = DADiskGetBSDName(whole) else { return nil }
        return String(cString: name)
    }
}
