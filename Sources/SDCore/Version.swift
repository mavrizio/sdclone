import Foundation

/// Versione di SD Clone: unica fonte per l'app, il comando `sdclone` e l'Info.plist (letta da scripts/build-app.sh).
public enum SDCloneVersion {
    /// Versione per le persone (CFBundleShortVersionString).
    public static let marketing = "1.0.0"
    /// Numero di build, da aumentare a ogni pacchetto distribuito (CFBundleVersion).
    public static let build = "3"

    public static var full: String { "\(marketing) (\(build))" }
}
