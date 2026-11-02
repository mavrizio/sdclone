import Foundation

/// Argomenti della Guida. Il testo accetta il markdown semplice di SwiftUI (**grassetto**, `codice`).
struct HelpTopic: Identifiable, Hashable {
    enum Block: Hashable {
        case text(String)
        case steps([String])
        case command(String)
        case tip(String)
        case warning(String)
    }

    let id: String
    let title: String
    let symbol: String
    let summary: String
    let blocks: [Block]

    /// Testo su cui cerca il campo di ricerca.
    var searchableText: String {
        ([title, summary] + blocks.map {
            switch $0 {
            case .text(let s), .command(let s), .tip(let s), .warning(let s): return s
            case .steps(let list): return list.joined(separator: " ")
            }
        }).joined(separator: " ").lowercased()
    }
}

enum HelpContent {
    /// Percorso del comando da terminale dentro l'app (per gli esempi).
    static var cliPath: String {
        let inBundle = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/sdclone-cli").path
        return FileManager.default.fileExists(atPath: inBundle) ? inBundle : "/Applications/SD Clone.app/Contents/MacOS/sdclone-cli"
    }

    static let topics: [HelpTopic] = [
        HelpTopic(
            id: "start", title: "Primi passi", symbol: "sparkles",
            summary: "Cosa serve e come è organizzata l'app.",
            blocks: [
                .text("SD Clone salva, prepara e scrive le schede SD dei Raspberry Pi. A sinistra trovi le quattro sezioni, nell'ordine in cui di solito si usano:"),
                .steps([
                    "**Backup**: copia una scheda in un file immagine (.img o .img.xz) sul Mac.",
                    "**Ottimizza**: riduce, ripulisce e comprime un'immagine prima di distribuirla.",
                    "**Ripristina**: scrive un'immagine su una scheda e la verifica.",
                    "**Archivio**: le immagini salvate, pronte da ripristinare o ottimizzare.",
                ]),
                .text("Serve un lettore di schede SD, interno o USB. SD Clone mostra **solo** schede esterne o rimovibili: i dischi del Mac non compaiono e non possono essere scelti."),
                .tip("La prima volta macOS chiede di concedere a SD Clone l'«Accesso completo al disco»: vedi l'argomento **Permessi di macOS**."),
            ]),
        HelpTopic(
            id: "backup", title: "Fare un backup", symbol: "square.and.arrow.down.fill",
            summary: "Copiare una scheda in un file immagine.",
            blocks: [
                .steps([
                    "Inserisci la scheda: compare nell'elenco con le sue partizioni.",
                    "Scegli la cartella (Documenti, Scrivania, Google Drive…) e il nome del file.",
                    "Come formato lascia **Compressa .img.xz** se vuoi un file 3-5 volte più piccolo.",
                    "Premi **Avvia il backup** e inserisci la password di amministratore quando macOS la chiede.",
                ]),
                .text("Viene copiata la scheda fino alla fine dell'ultima partizione: una scheda da 64 GB con 16 GB di partizioni produce un'immagine da 16 GB. Accanto all'immagine viene salvato un file **.sha256** con l'impronta dei dati, usata poi per verificare i ripristini."),
                .tip("Spegni il Raspberry con `sudo poweroff` prima di estrarre la scheda: un backup di un sistema spento male può contenere file a metà."),
            ]),
        HelpTopic(
            id: "optimize", title: "Ottimizzare un'immagine", symbol: "wand.and.stars",
            summary: "Ridurre, ripulire e comprimere un backup.",
            blocks: [
                .text("Ottimizza prepara un'immagine da distribuire, per esempio la «golden image» da cui nascono le schede della flotta. Crea sempre **file nuovi**: l'immagine di partenza non viene mai modificata e nessun file viene sovrascritto."),
                .steps([
                    "**Riduci al minimo**: porta la partizione Linux allo spazio davvero usato (come PiShrink). Un'immagine da 16 GB con 4 GB di dati diventa di circa 6 GB.",
                    "**Togli le cronologie**: cancella `.bash_history`, `.python_history`, `.lesshst`, `.viminfo` e simili da `/root` e dalle cartelle in `/home`.",
                    "**Comprimi in .xz**: il file da caricare su Drive, leggibile anche da Raspberry Pi Imager.",
                ]),
                .text("Il risultato si chiama `NOME.min.img.xz`, con il suo `.sha256`, e viene controllato con `e2fsck` prima di essere salvato. Va bene anche partire da un `.img.xz`."),
                .warning("Un'immagine ridotta **non si espande da sola** sul Raspberry: dopo il primo avvio va espansa a mano (vedi **Sul Raspberry Pi**)."),
                .text("Riduci e Togli le cronologie usano gli strumenti gratuiti **e2fsprogs**. Se mancano, installali una volta sola con Homebrew:"),
                .command("brew install e2fsprogs"),
            ]),
        HelpTopic(
            id: "restore", title: "Ripristinare una scheda", symbol: "arrow.uturn.backward.circle.fill",
            summary: "Scrivere un'immagine su una scheda e verificarla.",
            blocks: [
                .steps([
                    "Trascina un file .img o .img.xz nella finestra, oppure sceglilo dall'Archivio.",
                    "Scegli la scheda da scrivere: deve essere grande almeno quanto l'immagine.",
                    "Premi **Ripristina…** e, per conferma, scrivi il nome del disco (per esempio `disk4`).",
                    "Attendi scrittura e verifica: alla fine la scheda viene espulsa da sola.",
                ]),
                .warning("Il ripristino **cancella tutto** il contenuto della scheda scelta. Controlla nome e capacità prima di confermare."),
                .text("Dopo la scrittura SD Clone rilegge l'intera scheda e confronta l'impronta SHA256 con quella dell'immagine: se una sola cifra è diversa il ripristino viene segnalato come non riuscito. Durante il lavoro macOS non può montare la scheda, così nessun altro programma la modifica prima della verifica."),
            ]),
        HelpTopic(
            id: "library", title: "Archivio e Google Drive", symbol: "tray.full.fill",
            summary: "Dove finiscono le immagini e come condividerle.",
            blocks: [
                .text("L'Archivio mostra le immagini della cartella dei backup (di serie `~/Documents/SDClone`, modificabile nelle Impostazioni). Da qui puoi ripristinare, ottimizzare, comprimere, mostrare nel Finder o spostare nel Cestino."),
                .text("Per condividere un'immagine con i colleghi salvala, o spostala, in una cartella di **Google Drive** sincronizzata sul Mac: SD Clone la propone fra le destinazioni. Carica sempre anche il file `.sha256` che sta accanto."),
                .tip("SD Clone scrive i file direttamente con il loro nome definitivo solo quando sono completi: Drive non carica mai un'immagine a metà."),
            ]),
        HelpTopic(
            id: "raspberry", title: "Sul Raspberry Pi", symbol: "cpu",
            summary: "Primo avvio, espansione e controlli.",
            blocks: [
                .text("Dopo aver scritto un'immagine **ridotta**, al primo avvio il filesystem occupa solo lo spazio dell'immagine. Per usare tutta la scheda:"),
                .command("sudo raspi-config nonint do_expand_rootfs && sudo reboot"),
                .text("Dopo il riavvio controlla con:"),
                .command("df -h /"),
                .warning("Due schede nate dalla stessa immagine hanno lo stesso nome di rete, le stesse chiavi SSH e lo stesso machine-id. Non accenderle insieme sulla stessa rete e rigenera chiavi e machine-id su ogni copia."),
                .command("sudo rm /etc/ssh/ssh_host_* && sudo dpkg-reconfigure openssh-server"),
                .command("sudo rm /etc/machine-id && sudo systemd-machine-id-setup && sudo reboot"),
            ]),
        HelpTopic(
            id: "permissions", title: "Permessi di macOS", symbol: "lock.shield.fill",
            summary: "Accesso completo al disco e password di amministratore.",
            blocks: [
                .text("Per leggere e scrivere direttamente una scheda servono due cose: la **password di amministratore**, chiesta da macOS a ogni backup o ripristino, e l'**Accesso completo al disco**, da concedere una volta sola."),
                .steps([
                    "Apri Impostazioni di Sistema › Privacy e sicurezza › **Accesso completo al disco**.",
                    "Attiva **SD Clone** (con il pulsante **+** se non è nell'elenco).",
                    "Chiudi e riapri SD Clone.",
                ]),
                .tip("Dopo un aggiornamento di SD Clone macOS può considerarla un'app nuova: se compare di nuovo l'avviso, spegni e riaccendi l'interruttore."),
                .text("Ottimizza e Comprimi lavorano solo su file e non chiedono password."),
            ]),
        HelpTopic(
            id: "troubleshooting", title: "Problemi frequenti", symbol: "stethoscope",
            summary: "Cosa fare quando qualcosa non va.",
            blocks: [
                .text("**La scheda non compare.** Controlla che sia inserita bene e che il lettore funzioni (deve vederla anche Utility Disco). I dischi interni del Mac non compaiono mai, per sicurezza."),
                .text("**«macOS ha bloccato l'accesso».** Manca l'Accesso completo al disco: vedi **Permessi di macOS**."),
                .text("**«La scheda è occupata».** Un programma (Spotlight, un antivirus, un driver ext4) la sta usando. SD Clone riprova da solo e, se serve, forza lo smontaggio. Se non basta, espelli la scheda dal Finder e reinseriscila."),
                .text("**«Verifica fallita».** I dati riletti non coincidono con quelli scritti: la scheda può essere difettosa o contraffatta (capacità falsa). Riprova; se si ripete, cambia scheda. **Non usare** una scheda che non ha superato la verifica."),
                .text("**«Spazio insufficiente».** Libera spazio o scegli un'altra cartella. Ottimizza ha bisogno temporaneamente di circa il doppio della dimensione dell'immagine sul disco del Mac."),
                .text("**Il Raspberry non si avvia.** Riscrivi la scheda e verifica che l'immagine sia giusta per quel modello. Se l'immagine è ridotta, ricordati di espanderla dopo il primo avvio riuscito."),
            ]),
        HelpTopic(
            id: "terminal", title: "Da terminale", symbol: "terminal.fill",
            summary: "Il comando sdclone per gli utenti esperti.",
            blocks: [
                .text("Tutto ciò che fa l'app si può fare anche dal Terminale con il comando incluso in SD Clone:"),
                .command("\"\(cliPath)\" list"),
                .command("sudo \"\(cliPath)\" backup disk4 --xz"),
                .command("\"\(cliPath)\" optimize ~/Documents/SDClone/pi.img --clean"),
                .command("sudo \"\(cliPath)\" restore ~/Documents/SDClone/pi.min.img.xz disk4"),
                .text("Lanciato senza argomenti mostra l'elenco completo delle opzioni."),
            ]),
        HelpTopic(
            id: "shortcuts", title: "Scorciatoie da tastiera", symbol: "command",
            summary: "Per andare più veloci.",
            blocks: [
                .steps([
                    "**⌘1 … ⌘4**: Backup, Ottimizza, Ripristina, Archivio.",
                    "**⌘O**: apri un'immagine da ripristinare.  **⇧⌘O**: apri un'immagine da ottimizzare.",
                    "**⌘E**: espelli la scheda selezionata.",
                    "**⌥⌘B**: mostra la cartella dei backup nel Finder.",
                    "**⌘,**: Impostazioni.  **⌘?**: questa Guida.",
                    "**⏎** avvia l'operazione della schermata, **⎋** chiude le finestre di conferma.",
                ]),
            ]),
    ]
}
