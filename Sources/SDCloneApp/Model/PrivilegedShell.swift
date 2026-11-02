import Foundation

/// Esegue un comando come amministratore col dialogo di autorizzazione standard di macOS.
/// E' la soluzione provvisoria prima dell'helper privilegiato (SMAppService): il comando e' sempre
/// l'eseguibile `sdclone` incluso nell'app, che a sua volta controlla `SafetyPolicy`.
enum PrivilegedShell {
    enum Result {
        case finished(output: String)
        case authCancelled
        case failed(String)
    }

    static func run(arguments: [String], prompt: String) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let command = arguments.map(shellQuote).joined(separator: " ")
                let source = "do shell script \"\(appleScriptEscape(command))\" with prompt \"\(appleScriptEscape(prompt))\" with administrator privileges"
                var error: NSDictionary?
                let output = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    let code = error[NSAppleScript.errorNumber] as? Int
                    if code == -128 {
                        continuation.resume(returning: .authCancelled)
                    } else {
                        let message = (error[NSAppleScript.errorMessage] as? String) ?? "errore sconosciuto"
                        continuation.resume(returning: .failed(message))
                    }
                } else {
                    continuation.resume(returning: .finished(output: output?.stringValue ?? ""))
                }
            }
        }
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// L'eseguibile `sdclone` accanto all'app (nel pacchetto: Contents/MacOS/sdclone-cli).
    static func helperURL() -> URL? {
        guard let dir = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
        for name in ["sdclone-cli", "sdclone"] {
            let url = dir.appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }
}
